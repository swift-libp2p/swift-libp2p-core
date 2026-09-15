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

public final class PeerRecord: Record, Hashable, Sendable {

    //static let domain:String = "libp2p-peer-record"
    static let codec: Codecs = .libp2p_peer_record

    public let peerID: PeerID
    public let multiaddrs: [Multiaddr]
    public let sequenceNumber: UInt64

    public var domain: String { PeerRecord.codec.name }
    public var codec: Codecs { PeerRecord.codec }

    public init(
        peerID: PeerID,
        multiaddrs: [Multiaddr],
        sequenceNumber: UInt64 = (UInt64(Date().timeIntervalSince1970 * 1000))
    ) {
        self.peerID = peerID
        self.multiaddrs = multiaddrs
        self.sequenceNumber = sequenceNumber
    }

    public init(marshaledData: Data) throws {
        let pr = try PeerRecordMessage(serializedBytes: marshaledData)
        self.peerID = try PeerID(fromBytesID: pr.peerID.byteArray)
        self.multiaddrs = try pr.addresses.map {
            try Multiaddr($0.multiaddr)
        }
        self.sequenceNumber = pr.seq
    }

    public init(marshaledData: Data, withPublicKey pubKey: Data) throws {
        let pr = try PeerRecordMessage(serializedBytes: marshaledData)
        let validatingPubKey = try PeerID(marshaledPublicKey: pubKey)
        guard pr.peerID.byteArray == validatingPubKey.id else {
            // PubKey bytes don't match
            throw Errors.noPublicKey
        }
        self.peerID = validatingPubKey

        // Instead of failing if we fail to decode any Multiaddr
        // let's only fail if we fail to decode all of them.
        var err: Error? = nil
        self.multiaddrs = pr.addresses.compactMap {
            do {
                return try Multiaddr($0.multiaddr)
            } catch {
                err = error
                return nil
            }
        }
        if self.multiaddrs.isEmpty, let err = err { throw err }

        self.sequenceNumber = pr.seq
    }

    public func marshal() throws -> [UInt8] {
        var rec = PeerRecordMessage()
        rec.peerID = Data(self.peerID.id)
        rec.addresses = try self.multiaddrs.map {
            var addr = PeerRecordMessage.AddressInfo()
            addr.multiaddr = try $0.binaryPacked()
            return addr
        }
        rec.seq = self.sequenceNumber
        return try rec.serializedData().byteArray
    }

    public func equals<R>(_ r: R) -> Bool where R: Record {
        self.peerID == r.peerID
            && self.multiaddrs == r.multiaddrs
            && self.sequenceNumber == r.sequenceNumber
    }

    public static func == (lhs: PeerRecord, rhs: PeerRecord) -> Bool {
        lhs.equals(rhs)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.peerID.id)
        hasher.combine(self.multiaddrs)
    }

    public func seal(withPrivateKey key: PeerID) throws -> Envelope {
        try SealedEnvelope(record: self, signedWithKey: key)
    }

    public func unsignedPayload() throws -> [UInt8] {
        (domain.utf8).uVarIntLengthPrefixed
            + self.codec.envelopePayloadType.uVarIntLengthPrefixed
            + (try self.marshal()).uVarIntLengthPrefixed
    }
}

extension Codecs {
    /// The raw multicodec code as big-endian bytes (`0x0301` → `[0x03, 0x01]`).
    ///
    /// - NOTE: go-libp2p and js-libp2p use the codec's raw bytes, not its uVarInt
    /// encoding (which for `libp2p_peer_record` would be `[0x81, 0x06]`), as an
    /// Envelope's `payload_type`, so we do the same for interop. Decoding
    /// `[0x03, 0x01]` as a uVarInt multicodec prefix resolves to `cidv3` instead of
    /// `libp2p_peer_record`, which is why `SealedEnvelope` accepts both during
    ///  verification.
    public var envelopePayloadType: [UInt8] {
        var value = self.rawValue
        var bytes: [UInt8] = []
        repeat {
            bytes.insert(UInt8(truncatingIfNeeded: value), at: 0)
            value >>= 8
        } while value > 0
        return bytes
    }
}

extension PeerRecord: CustomStringConvertible {
    public var description: String {
        let header = "--- 👥 Peer Record (Codec/Domain: \(self.domain)) 👥 ---"
        return """
            \(header)
            PeerID: \(peerID.b58String)
            Multiaddr:
            - \( self.multiaddrs.map { $0.description }.joined(separator: "\n- ") )
            Sequence number: \(self.sequenceNumber)
            \(String(repeating: "-", count: header.count + 2))
            """
    }
}
