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

import Multiaddr
import PeerID

public protocol Record: Equatable, Sendable {
    var peerID: PeerID { get }
    var multiaddrs: [Multiaddr] { get }
    var sequenceNumber: UInt64 { get }

    var domain: String { get }
    var codec: Codecs { get }

    /// Default Record Initializer
    init(peerID: PeerID, multiaddrs: [Multiaddr], sequenceNumber: UInt64)

    /// Marshal a record to be used in a libp2p envelope
    func marshal() throws -> [UInt8]

    /// Verifies if the other Record is identical to this one
    func equals<R: Record>(_ r: R) -> Bool

    func unsignedPayload() -> [UInt8]

    /// Signs / Seals this `Record` in an `Envelope` using the private key provided
    ///
    /// - Parameters:
    ///   - withPrivateKey: The PeerID containing the private key for signing
    /// - Returns: An Envelope that contains the signed Record
    /// - Throws: An error of type Record.Errors
    func seal(withPrivateKey: PeerID) throws -> Envelope
}

/// An Envelope contains a signed Record
public protocol Envelope: CustomStringConvertible, Sendable {
    var pubKey: PeerID { get }

    var payloadType: [UInt8] { get }

    var rawPayload: [UInt8] { get }

    var signature: [UInt8] { get }

    //var record:Record { get }

    /// Use this initializer to create a Signed / Sealed Envelope with a Record and your local PeerID (must include a private key)
    ///
    /// - Parameters:
    ///   - record: A `Record` to sign and embed in an `Envelope`
    ///   - signedWithKey: An optional public key to verify the `Envelope`s signed `Record` against
    /// - Throws: An error of type Record.Errors
    ///
    /// Note:
    /// ```
    /// // You can also call the seal method on the `Record` you're interested in signing
    /// Record.seal(withPrivateKey:)
    /// ```
    init<R: Record>(record: R, signedWithKey key: PeerID) throws

    /// Takes a marshaled envelope, attempts to decode and verify the internal signature against the embedded public key or the specified public key
    ///
    /// - Parameters:
    ///   - marshaledEnvelope: A marshaled `Envelope`
    ///   - verifiedWithPubkey: An optional public key to verify the `Envelope`s signed `Record` against
    /// - Throws: An error of type Record.Errors
    ///
    /// Note: If this initializer doesn't fail, the Record within the envelope is verified
    init(marshaledEnvelope: [UInt8], verifiedWithPublicKey: [UInt8]?) throws

    func marshal() throws -> [UInt8]
}

public enum Errors: Error, CustomStringConvertible, Sendable {
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

//extension Envelope {
//    public var description: String {
//        return """
//            --- 💌 Sealed Envelope 💌 ---
//            PeerID: \(pubKey) (has pubKey: \(pubKey.keyPair?.publicKey != nil ? "true" : "false"))
//            Payload Type: \((try? Multicodec.getCodec(bytes: self.payloadType)) ?? self.payloadType.asString(base: .base16) )
//            Raw Payload: \(self.rawPayload.asString(base: .base16))
//            Signature: \(self.signature.asString(base: .base16))
//            -----------------------------
//            """
//    }
//}
