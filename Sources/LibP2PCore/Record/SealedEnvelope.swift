//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-libp2p open source project
//
// Copyright (c) 2022-2025 swift-libp2p project authors
// Licensed under MIT
//
// See LICENSE for license information
// See CONTRIBUTORS for the list of swift-libp2p project authors
//
// SPDX-License-Identifier: MIT
//
//===----------------------------------------------------------------------===//

import Foundation
import Multicodec
import SwiftProtobuf

// Envelope contains an arbitrary []byte payload, signed by a libp2p peer.
//
// Envelopes are signed in the context of a particular "domain", which is a
// string specified when creating and verifying the envelope. You must know the
// domain string used to produce the envelope in order to verify the signature
// and access the payload.
public final class SealedEnvelope: Envelope {

    // The public key that can be used to verify the signature and derive the peer id of the signer.
    //PublicKey crypto.PubKey
    public let pubKey: PeerID

    // A binary identifier that indicates what kind of data is contained in the payload.
    // TODO(yusef): enforce multicodec prefix
    //PayloadType []byte
    public let payloadType: [UInt8]

    // The envelope payload.
    //RawPayload []byte
    public let rawPayload: [UInt8]

    // The signature of the domain string :: type hint :: payload.
    //signature []byte
    public let signature: [UInt8]

    // the unmarshalled payload as a Record, cached on first access via the Record accessor method
    //cached         Record
    //unmarshalError error
    //unmarshalOnce  sync.Once
    lazy var cached: PeerRecord? = {
        nil
    }()

    /// Creates a new Signed & SealedEnvelope containing the specified Record, ready for marsahling and sending to remote peers...
    public init<R: Record>(record: R, signedWithKey key: PeerID) throws {
        guard let privKey = key.keyPair?.privateKey else {
            throw Errors.noPrivateKey
        }

        self.pubKey = record.peerID

        self.payloadType = [0x03, 0x01]  //record.codec.asVarInt

        self.rawPayload = try record.marshal()

        self.signature = try privKey.sign(message: Data(record.unsignedPayload())).bytes
    }

    /// Takes a marshalled / serialized Envelope object
    public init(marshaledEnvelope bytes: [UInt8], verifiedWithPublicKey pubKey: [UInt8]? = nil) throws {
        //print("Attempting to instantiate a SealedEnvelope from marshaled data")
        let env = try EnvelopeMessage(contiguousBytes: bytes)
        //print("We have an Envelope, attempting to extract PublicKey")
        if let pub = pubKey {
            self.pubKey = try PeerID(marshaledPublicKey: Data(pub))
            //guard self.pubKey.keyPair?.publicKey.data == env.publicKey.data else {
            //    //pubkey mismatch...
            //    print( self.pubKey.keyPair?.publicKey.data.asString(base: .base16) )
            //    print(" =/= ")
            //    print( env.publicKey.data.asString(base: .base16) )
            //    throw Errors.noPublicKey
            //}
        } else {
            self.pubKey = try PeerID(marshaledPublicKey: env.publicKey.serializedData())
        }

        //print("We have a Public Key, proceeding with signature verification")
        self.payloadType = env.payloadType.bytes

        self.rawPayload = env.payload.bytes

        self.signature = env.signature.bytes

        guard try verifySignature() else {
            throw Errors.invalidSignature
        }
    }

    public func marshal() throws -> [UInt8] {
        guard let pubKey = self.pubKey.keyPair?.publicKey else {
            throw Errors.noPublicKey
        }
        var env = EnvelopeMessage()
        //var pub = Envelope.PublicKey()
        //pub.type = .rsa
        //pub.data = try pubKey.marshal()
        //env.publicKey = pub
        env.publicKey = try EnvelopeMessage.PublicKey(contiguousBytes: pubKey.marshal())
        //print("Envelope Marshalled PubKey:")
        //print(pub)
        env.payloadType = Data(self.payloadType)
        env.payload = Data(self.rawPayload)
        env.signature = Data(self.signature)

        return try [UInt8](env.serializedData())
    }

    private func verifySignature() throws -> Bool {
        guard let type = try? Multicodec.getCodecEnum(bytes: self.payloadType) else { throw Errors.emptyPayloadType }
        guard let publicKey = self.pubKey.keyPair?.publicKey else { throw Errors.noPublicKey }
        switch type {
        /// - Note: We check for cidv3 here due to go-libp2p's usage of [0x03, 0x01] libp2p-peer-record hardcoded prefix values...
        case .cidv3, .libp2p_peer_record:  //PeerRecord
            //print("Looks like we have a PeerRecord as our underlying Record Type. Attempting to unmarshal and verify signature")
            let pRec = try PeerRecord(marshaledData: Data(self.rawPayload))
            //print("Unmarshaled PeerRecord successfully, proceeding with signature verification")
            return try publicKey.verify(signature: Data(self.signature), for: Data(pRec.unsignedPayload()))

        default:
            throw Errors.emptyPayloadType
        }
    }

    public enum Errors: Error, CustomStringConvertible {
        case noPrivateKey
        case noPublicKey
        case emptyDomain
        case emptyPayloadType
        case invalidSignature

        public var description: String {
            switch self {
            case .noPrivateKey: return "the PeerID provided doesn't contain a private key"
            case .noPublicKey: return "the PeerID provided doesn't contain a public key"
            case .emptyDomain: return "envelope domain must not be empty"
            case .emptyPayloadType: return "payloadType must not be empty"
            case .invalidSignature: return "invalid signature or incorrect domain"
            }
        }
    }
}

extension SealedEnvelope: CustomStringConvertible {
    public var description: String {
        """
        --- 💌 Sealed Envelope 💌 ---
        PeerID: \(pubKey) (has pubKey: \(pubKey.keyPair?.publicKey != nil ? "true" : "false"))
        Payload Type: \((try? Multicodec.getCodec(bytes: self.payloadType)) ?? self.payloadType.asString(base: .base16) )
        Raw Payload: \(self.rawPayload.asString(base: .base16))
        Signature: \(self.signature.asString(base: .base16))
        -----------------------------
        """
    }
}
