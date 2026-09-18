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

import LibP2PCrypto
import Testing

@testable import LibP2PCore

@Suite("PeerRecord Tests")
struct PeerRecordTests {

    /// The envelope payload type must be the raw big-endian bytes of the
    /// libp2p-peer-record multicodec (0x0301), matching go-libp2p's and
    /// js-libp2p's hardcoded [0x03, 0x01] prefix.
    @Test func envelopePayloadTypeMatchesGoLibp2p() throws {
        #expect(Codecs.libp2p_peer_record.envelopePayloadType == [0x03, 0x01])
    }

    /// The unsigned payload (the bytes that get signed when sealing a Record
    /// in an Envelope) must follow the libp2p signed-envelope spec:
    ///
    /// `varint(len(domain)) + domain + varint(len(payload_type)) + payload_type + varint(len(payload)) + payload`
    @Test func unsignedPayloadLayout() throws {
        let peerID = try PeerID(.Ed25519)
        let record = PeerRecord(
            peerID: peerID,
            multiaddrs: [try Multiaddr("/ip4/127.0.0.1/tcp/4001")],
            sequenceNumber: 42
        )

        let marshaled = try record.marshal()

        var expected: [UInt8] = []
        // Domain: "libp2p-peer-record" is 18 (0x12) bytes long
        expected += [0x12] + Array("libp2p-peer-record".utf8)
        // Payload type: 2 bytes, the raw big-endian bytes of the 0x0301 multicodec
        expected += [0x02, 0x03, 0x01]
        // Payload: the length-prefixed, marshaled PeerRecord protobuf
        expected += UInt64(marshaled.count).varIntBytes + marshaled

        #expect(try record.unsignedPayload() == expected)
    }

    @Test func sealAndVerifyRoundTrip() throws {
        let peerID = try PeerID(.Ed25519)
        let record = PeerRecord(
            peerID: peerID,
            multiaddrs: [try Multiaddr("/ip4/192.168.1.1/tcp/10000")],
            sequenceNumber: 7
        )

        let envelope = try record.seal(withPrivateKey: peerID)
        #expect(envelope.payloadType == [0x03, 0x01])

        // The initializer throws if the embedded signature doesn't verify
        let restored = try SealedEnvelope(
            marshaledEnvelope: envelope.marshal(),
            verifiedWithPublicKey: nil
        )
        #expect(restored.payloadType == [0x03, 0x01])

        let restoredRecord = try PeerRecord(marshaledData: Data(restored.rawPayload))
        #expect(restoredRecord.equals(record))
    }
}
