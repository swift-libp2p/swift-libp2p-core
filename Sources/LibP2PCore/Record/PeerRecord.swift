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
    static let codec: Codecs = .libp2p_peer_record  //.libp2p_peer_record

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
        let pr = try PeerRecordMessage(contiguousBytes: marshaledData)
        self.peerID = try PeerID(fromBytesID: pr.peerID.bytes)
        self.multiaddrs = try pr.addresses.map {
            try Multiaddr($0.multiaddr)
        }
        self.sequenceNumber = pr.seq
    }

    public init(marshaledData: Data, withPublicKey pubKey: Data) throws {
        let pr = try PeerRecordMessage(contiguousBytes: marshaledData)
        let validatingPubKey = try PeerID(marshaledPublicKey: pubKey)
        guard pr.peerID.bytes == validatingPubKey.bytes else {
            print("Error: PubKey Bytes Don't Match")
            print(pr.peerID.bytes.asString(base: .base16))
            print(validatingPubKey.b58String)
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
        rec.peerID = Data(self.peerID.bytes)
        rec.addresses = try self.multiaddrs.map {
            var addr = PeerRecordMessage.AddressInfo()
            addr.multiaddr = try $0.binaryPacked()
            return addr
        }
        rec.seq = self.sequenceNumber
        return try rec.serializedData().bytes
    }

    public func equals<R>(_ r: R) -> Bool where R: Record {
        self.peerID == r.peerID
            && self.multiaddrs == r.multiaddrs
            && self.sequenceNumber == r.sequenceNumber
    }

    public static func == (lhs: PeerRecord, rhs: PeerRecord) -> Bool {
        lhs.equals(rhs)
    }

    public func seal(withPrivateKey key: PeerID) throws -> Envelope {
        try SealedEnvelope(record: self, signedWithKey: key)
    }

    /// - NOTE: go-libp2p seems to be using these [0x03, 0x01] hardcoded bytes to prefix libp2p-peer-records.
    /// When the Multicodec value for libp2p-peer-record is actually 0x0301 which when placed in a uVarInt buffer results in a multicodec prefix of [0x81, 0x06]
    /// This also results in the Multicodec resolving to cidv3 instead of libp2p-peer-record during decoding.
    /// I guess for now we just use the hardcoded values...
    public func unsignedPayload() -> [UInt8] {
        uVarIntLengthPrefixed(domain.data(using: .utf8)!.bytes)
            + uVarIntLengthPrefixed([0x03, 0x01])
            //+ uVarIntLengthPrefixed( Multicodec.getPrefix(multiCodec: PeerRecord.codec) )
            + uVarIntLengthPrefixed(try! self.marshal())
    }

    private func uVarIntLengthPrefixed(_ bytes: [UInt8]) -> [UInt8] {
        putUVarInt(UInt64(bytes.count)) + bytes
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
