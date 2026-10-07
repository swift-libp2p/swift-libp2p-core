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
import SwiftProtobuf
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

    /// Another implementation may sign a payload we'd never produce ourselves (here: an unknown
    /// field). The signature must be verified over the bytes received, not a re-marshaled record,
    /// and a rebuilt envelope must carry the payload unchanged so it still verifies when forwarded.
    @Test func verifiesPayloadWithUnknownFieldsAndForwardsItUnchanged() throws {
        let peerID = try PeerID(.Ed25519)
        var message = PeerRecordMessage()
        message.peerID = Data(peerID.id)
        message.seq = 9
        var address = PeerRecordMessage.AddressInfo()
        address.multiaddr = try Multiaddr("/ip4/10.0.0.1/tcp/4001").binaryPacked()
        message.addresses = [address]
        // Field 15, varint 1: unknown to our PeerRecord, so re-marshaling would drop it.
        let payload = try [UInt8](message.serializedData()) + [0x78, 0x01]

        let bytes = try Self.envelope(signing: payload, with: peerID)
        let envelope = try SealedEnvelope(marshaledEnvelope: bytes, verifiedWithPublicKey: nil)

        #expect(envelope.rawPayload == payload)

        let forwarded = try SealedEnvelope(marshaledEnvelope: envelope.marshal(), verifiedWithPublicKey: nil)
        #expect(forwarded.rawPayload == payload)
        #expect(forwarded.signature == envelope.signature)
    }

    /// A multiaddr we can't decode doesn't make a correctly signed envelope invalid.
    @Test func verifiesPayloadWithUndecodableMultiaddr() throws {
        let peerID = try PeerID(.Ed25519)
        var message = PeerRecordMessage()
        message.peerID = Data(peerID.id)
        message.seq = 3
        var address = PeerRecordMessage.AddressInfo()
        address.multiaddr = Data([0xFF, 0xFF, 0xFF])
        message.addresses = [address]
        let payload = try [UInt8](message.serializedData())

        let bytes = try Self.envelope(signing: payload, with: peerID)
        let envelope = try SealedEnvelope(marshaledEnvelope: bytes, verifiedWithPublicKey: nil)
        #expect(envelope.rawPayload == payload)
    }

    @Test func rejectsTamperedSignature() throws {
        let peerID = try PeerID(.Ed25519)
        let record = PeerRecord(
            peerID: peerID,
            multiaddrs: [try Multiaddr("/ip4/127.0.0.1/tcp/4001")],
            sequenceNumber: 1
        )
        var envelope = try EnvelopeMessage(serializedBytes: record.seal(withPrivateKey: peerID).marshal())
        envelope.signature[0] ^= 0xFF

        #expect(throws: RecordError.self) {
            try SealedEnvelope(marshaledEnvelope: [UInt8](envelope.serializedData()), verifiedWithPublicKey: nil)
        }
    }

    @Test func acceptsExpectedPublicKeyThatMatchesTheSigner() throws {
        let signer = try PeerID(.Ed25519)
        let record = PeerRecord(peerID: signer, multiaddrs: [], sequenceNumber: 1)
        let bytes = try record.seal(withPrivateKey: signer).marshal()

        let envelope = try SealedEnvelope(
            marshaledEnvelope: bytes,
            verifiedWithPublicKey: try signer.marshalPublicKey()
        )
        #expect(envelope.pubKey.id == signer.id)
    }

    /// An envelope that's validly signed, but by someone other than the peer we expected, is rejected.
    @Test func rejectsExpectedPublicKeyThatDoesNotMatchTheSigner() throws {
        let signer = try PeerID(.Ed25519)
        let someoneElse = try PeerID(.Ed25519)
        let record = PeerRecord(peerID: signer, multiaddrs: [], sequenceNumber: 1)
        let bytes = try record.seal(withPrivateKey: signer).marshal()

        #expect(throws: RecordError.self) {
            try SealedEnvelope(marshaledEnvelope: bytes, verifiedWithPublicKey: try someoneElse.marshalPublicKey())
        }
    }

    /// Seals `payload` as a PeerRecord envelope by hand, bypassing `PeerRecord.marshal()`.
    private static func envelope(signing payload: [UInt8], with peerID: PeerID) throws -> [UInt8] {
        let privateKey = try #require(peerID.keyPair?.privateKey)
        let publicKey = try #require(peerID.keyPair?.publicKey)
        let payloadType = Codecs.libp2p_peer_record.envelopePayloadType
        let unsigned = SealedEnvelope.signingPayload(
            domain: "libp2p-peer-record",
            payloadType: payloadType,
            payload: payload
        )

        var envelope = EnvelopeMessage()
        envelope.publicKey = try EnvelopeMessage.PublicKey(serializedBytes: publicKey.marshal())
        envelope.payloadType = Data(payloadType)
        envelope.payload = Data(payload)
        envelope.signature = try privateKey.sign(message: Data(unsigned))
        return try [UInt8](envelope.serializedData())
    }
}
