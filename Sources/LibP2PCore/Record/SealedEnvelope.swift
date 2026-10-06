//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-libp2p open source project
//
// Copyright (c) 2022-2026 swift-libp2p project authors
// Licensed under MIT
//
// See LICENSE for license information
// See CONTRIBUTORS for the list of swift-libp2p project authors
//
// SPDX-License-Identifier: MIT
//
//===----------------------------------------------------------------------===//

import Foundation
import LibP2PCrypto
import Multicodec
import SwiftProtobuf

/// Envelope contains an arbitrary []byte payload, signed by a libp2p peer.
///
/// Envelopes are signed in the context of a particular "domain", which is a
/// string specified when creating and verifying the envelope. You must know the
/// domain string used to produce the envelope in order to verify the signature
/// and access the payload.
public struct SealedEnvelope: Envelope, Sendable {

    /// The public key that can be used to verify the signature and derive the peer id of the signer.
    public let pubKey: PeerID

    /// A binary identifier that indicates what kind of data is contained in the payload.
    public let payloadType: [UInt8]

    /// The envelope payload.
    public let rawPayload: [UInt8]

    /// The signature of the domain string :: type hint :: payload.
    public let signature: [UInt8]

    /// Creates a new Signed & SealedEnvelope containing the specified Record, ready for marsahling and sending to remote peers...
    public init<R: Record>(record: R, signedWithKey key: PeerID) throws {
        guard let privKey = key.keyPair?.privateKey else {
            throw RecordError.noPrivateKey
        }

        self.pubKey = record.peerID

        self.payloadType = record.codec.envelopePayloadType

        self.rawPayload = try record.marshal()

        let unsigned = Self.signingPayload(
            domain: record.domain,
            payloadType: self.payloadType,
            payload: self.rawPayload
        )
        self.signature = try [UInt8](privKey.sign(message: Data(unsigned)))
    }

    /// Takes a marshalled / serialized Envelope object
    ///
    /// - Note: The signature is always verified against the public key embedded in the envelope.
    /// - Parameters:
    ///   - bytes: The Envelope to process / verify and Seal
    ///   - pubKey: When provided, this envelope's signature must be verifiable using this pub key,
    ///     otherwise an `.invalidSignature` error will be thrown.
    public init(marshaledEnvelope bytes: [UInt8], verifiedWithPublicKey pubKey: [UInt8]? = nil) throws {
        let env = try EnvelopeMessage(serializedBytes: bytes)
        let embeddedKey = try PeerID(marshaledPublicKey: env.publicKey.serializedData())
        if let pub = pubKey {
            let expectedKey = try PeerID(marshaledPublicKey: Data(pub))
            guard expectedKey.id == embeddedKey.id else {
                throw RecordError.invalidSignature
            }
        }
        self.pubKey = embeddedKey

        self.payloadType = [UInt8](env.payloadType)

        self.rawPayload = [UInt8](env.payload)

        self.signature = [UInt8](env.signature)

        guard try verifySignature() else {
            throw RecordError.invalidSignature
        }
    }

    /// Rebuilds the envelope from its fields.
    ///
    /// The signature only covers the domain, `payloadType` and `rawPayload`, and those are kept
    /// exactly as received, so a rebuilt envelope verifies wherever the original did.
    public func marshal() throws -> [UInt8] {
        guard let pubKey = self.pubKey.keyPair?.publicKey else {
            throw RecordError.noPublicKey
        }

        let env = try EnvelopeMessage.with {
            $0.publicKey = try EnvelopeMessage.PublicKey(serializedBytes: pubKey.marshal())
            $0.payloadType = Data(self.payloadType)
            $0.payload = Data(self.rawPayload)
            $0.signature = Data(self.signature)
        }

        return try [UInt8](env.serializedData())
    }

    private func verifySignature() throws -> Bool {
        guard let type = try? self.payloadType.multicodec().codec else {
            throw RecordError.emptyPayloadType
        }
        guard let publicKey = self.pubKey.keyPair?.publicKey else { throw RecordError.noPublicKey }
        switch type {
        /// We check for cidv3 here due to go-libp2p's usage of [0x03, 0x01] libp2p-peer-record hardcoded prefix values...
        case .cidv3, .libp2p_peer_record:
            /// Make sure the payload is a PeerRecord
            _ = try PeerRecordMessage(serializedBytes: self.rawPayload)
            /// Reconstruct the received data (dont re-encode it, re-encoding can drop unknown fields or normalize addresses)
            let unsigned = Self.signingPayload(
                domain: PeerRecord.codec.name,
                payloadType: self.payloadType,
                payload: self.rawPayload
            )
            /// Verify the signature against the received bytes verbatim
            return try publicKey.verify(signature: Data(self.signature), for: Data(unsigned))

        default:
            // TODO: Throw an unknownPayloadType(codec) instead...
            throw RecordError.emptyPayloadType
        }
    }

    /// The bytes an envelope's signature covers, per the libp2p signed-envelope spec
    ///
    /// ```
    ///   varint(len(domain)) + domain
    /// + varint(len(payload_type)) + payload_type
    /// + varint(len(payload)) + payload
    /// ```
    static func signingPayload(domain: String, payloadType: [UInt8], payload: [UInt8]) -> [UInt8] {
        domain.utf8.uVarIntLengthPrefixed
            + payloadType.uVarIntLengthPrefixed
            + payload.uVarIntLengthPrefixed
    }
}
