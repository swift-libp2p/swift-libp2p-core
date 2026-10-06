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
import NIOConcurrencyHelpers
import NIOCore
import NIOEmbedded
import SwiftProtobuf
import Testing

@testable import LibP2PCore

@Suite("Signed PeerRecord Tests")
struct SignedPeerRecordTests {

    // MARK: - Helpers

    static func record(_ peer: PeerID, seq: UInt64, port: Int = 4001) throws -> PeerRecord {
        PeerRecord(peerID: peer, multiaddrs: [try Multiaddr("/ip4/127.0.0.1/tcp/\(port)")], sequenceNumber: seq)
    }

    /// A record sealed by its own peer, round-tripped through the wire format like a received one.
    static func envelope(_ peer: PeerID, seq: UInt64, port: Int = 4001) throws -> SealedEnvelope {
        let sealed = try record(peer, seq: seq, port: port).seal(withPrivateKey: peer)
        return try SealedEnvelope(marshaledEnvelope: sealed.marshal(), verifiedWithPublicKey: nil)
    }

    /// A validly signed envelope whose record names `named` instead of the signer.
    static func envelope(signedBy signer: PeerID, naming named: PeerID) throws -> SealedEnvelope {
        var message = PeerRecordMessage()
        message.peerID = Data(named.id)
        message.seq = 1
        var address = PeerRecordMessage.AddressInfo()
        address.multiaddr = try Multiaddr("/ip4/127.0.0.1/tcp/4001").binaryPacked()
        message.addresses = [address]
        let payload: [UInt8] = try message.serializedBytes()
        let payloadType = Codecs.libp2p_peer_record.envelopePayloadType

        let privateKey = try #require(signer.keyPair?.privateKey)
        let publicKey = try #require(signer.keyPair?.publicKey)
        let unsigned = SealedEnvelope.signingPayload(
            domain: PeerRecord.codec.name,
            payloadType: payloadType,
            payload: payload
        )
        var envelope = EnvelopeMessage()
        envelope.publicKey = try EnvelopeMessage.PublicKey(serializedBytes: publicKey.marshal())
        envelope.payloadType = Data(payloadType)
        envelope.payload = Data(payload)
        envelope.signature = try privateKey.sign(message: Data(unsigned))
        return try SealedEnvelope(marshaledEnvelope: envelope.serializedBytes(), verifiedWithPublicKey: nil)
    }

    // MARK: - PeerRecord(signedEnvelope:)

    @Test func peerRecordFromSignedEnvelope() throws {
        let peer = try PeerID(.Ed25519)
        let record = try PeerRecord(signedEnvelope: Self.envelope(peer, seq: 7))
        #expect(record.equals(try Self.record(peer, seq: 7)))
    }

    @Test func peerRecordFromEnvelopeNamingAnotherPeerThrows() throws {
        let signer = try PeerID(.Ed25519)
        let other = try PeerID(.Ed25519)
        let envelope = try Self.envelope(signedBy: signer, naming: other)
        #expect(throws: (any Error).self) { try PeerRecord(signedEnvelope: envelope) }
    }

    // MARK: - ComprehensivePeer

    @Test func insertingSignedRecordKeepsRecordAndEnvelope() throws {
        let peer = try PeerID(.Ed25519)
        let compPeer = ComprehensivePeer(id: peer)
        let envelope = try Self.envelope(peer, seq: 1)

        #expect(try compPeer.insert(signedRecord: envelope, keepingMostRecent: 3))
        #expect(compPeer.records.map(\.sequenceNumber) == [1])
        #expect(try compPeer.mostRecentSignedRecord?.marshal() == envelope.marshal())
        #expect(compPeer.signedRecords.count == 1)

        // The same envelope again is a duplicate.
        #expect(try compPeer.insert(signedRecord: envelope, keepingMostRecent: 3) == false)
    }

    @Test func envelopeAttachesToMatchingUnsignedRecord() throws {
        let peer = try PeerID(.Ed25519)
        let compPeer = ComprehensivePeer(id: peer)
        compPeer.insert(record: try Self.record(peer, seq: 1), keepingMostRecent: 3)
        #expect(compPeer.records.count == 1)
        #expect(compPeer.mostRecentSignedRecord == nil)

        #expect(try compPeer.insert(signedRecord: Self.envelope(peer, seq: 1), keepingMostRecent: 3))
        #expect(compPeer.records.count == 1)
        #expect(compPeer.mostRecentSignedRecord != nil)
    }

    @Test func envelopeDoesNotAttachToADifferentRecordWithTheSameSequenceNumber() throws {
        let peer = try PeerID(.Ed25519)
        let compPeer = ComprehensivePeer(id: peer)
        compPeer.insert(record: try Self.record(peer, seq: 1, port: 1111), keepingMostRecent: 3)

        #expect(
            try compPeer.insert(signedRecord: Self.envelope(peer, seq: 1, port: 2222), keepingMostRecent: 3) == false
        )
        #expect(compPeer.mostRecentSignedRecord == nil)
        #expect(compPeer.records.first?.multiaddrs == [try Multiaddr("/ip4/127.0.0.1/tcp/1111")])
    }

    /// A peer first learned by its traditional (SHA-256) ID must still accept envelopes whose record
    /// embeds its key, the two IDs are different bytes for the same peer.
    @Test func envelopeAttachesToAPeerKnownByItsSHA256ID() throws {
        let peer = try PeerID(.Ed25519)
        let sha256ID = try PeerID(cid: try peer.traditionalB58String())
        try #require(sha256ID.id != peer.id)
        let compPeer = ComprehensivePeer(id: sha256ID)

        #expect(try compPeer.insert(signedRecord: Self.envelope(peer, seq: 1), keepingMostRecent: 3))
        #expect(compPeer.mostRecentSignedRecord != nil)

        let restored = ComprehensivePeer(id: sha256ID, signedRecords: [try Self.envelope(peer, seq: 2)])
        #expect(restored.signedRecords.count == 1)
    }

    @Test func envelopeForAnotherPeerIsRejected() throws {
        let compPeer = ComprehensivePeer(id: try PeerID(.Ed25519))
        let other = try PeerID(.Ed25519)

        #expect(try compPeer.insert(signedRecord: Self.envelope(other, seq: 1), keepingMostRecent: 3) == false)
        #expect(compPeer.records.isEmpty)
        #expect(compPeer.signedRecords.isEmpty)
    }

    @Test func insertingAnEnvelopeThatNamesAnotherPeerThrows() throws {
        let signer = try PeerID(.Ed25519)
        let compPeer = ComprehensivePeer(id: signer)
        let envelope = try Self.envelope(signedBy: signer, naming: try PeerID(.Ed25519))

        #expect(throws: (any Error).self) { try compPeer.insert(signedRecord: envelope, keepingMostRecent: 3) }
        #expect(compPeer.records.isEmpty)
    }

    @Test func trimmingDropsTheEnvelopesOfTrimmedRecords() throws {
        let peer = try PeerID(.Ed25519)
        let compPeer = ComprehensivePeer(id: peer)
        for seq: UInt64 in 1...3 {
            try compPeer.insert(signedRecord: Self.envelope(peer, seq: seq), keepingMostRecent: 3)
        }
        #expect(compPeer.signedRecords.count == 3)

        compPeer.trimRecords(keepingMostRecent: 1)
        #expect(compPeer.records.map(\.sequenceNumber) == [3])
        #expect(try compPeer.signedRecords.map { try PeerRecord(signedEnvelope: $0).sequenceNumber } == [3])

        // Older than everything we're keeping, so it's trimmed straight away along with its envelope.
        #expect(try compPeer.insert(signedRecord: Self.envelope(peer, seq: 2), keepingMostRecent: 1) == false)
        #expect(compPeer.signedRecords.count == 1)
    }

    @Test func removeAllRecordsDropsEnvelopes() throws {
        let peer = try PeerID(.Ed25519)
        let compPeer = ComprehensivePeer(id: peer)
        try compPeer.insert(signedRecord: Self.envelope(peer, seq: 1), keepingMostRecent: 3)

        compPeer.removeAllRecords()
        #expect(compPeer.records.isEmpty)
        #expect(compPeer.mostRecentSignedRecord == nil)

        // A fresh record with the same sequence number can be inserted again.
        #expect(try compPeer.insert(signedRecord: Self.envelope(peer, seq: 1), keepingMostRecent: 3))
    }

    @Test func mostRecentSignedRecordIgnoresNewerUnsignedRecords() throws {
        let peer = try PeerID(.Ed25519)
        let compPeer = ComprehensivePeer(id: peer)
        try compPeer.insert(signedRecord: Self.envelope(peer, seq: 1), keepingMostRecent: 3)
        try compPeer.insert(signedRecord: Self.envelope(peer, seq: 2), keepingMostRecent: 3)
        compPeer.insert(record: try Self.record(peer, seq: 3), keepingMostRecent: 3)

        let mostRecent = try #require(compPeer.mostRecentSignedRecord)
        #expect(try PeerRecord(signedEnvelope: mostRecent).sequenceNumber == 2)
        #expect(try compPeer.signedRecords.map { try PeerRecord(signedEnvelope: $0).sequenceNumber } == [2, 1])
    }

    @Test func initRestoresSignedRecordsAndCopyKeepsThem() throws {
        let peer = try PeerID(.Ed25519)
        let other = try PeerID(.Ed25519)
        let compPeer = ComprehensivePeer(
            id: peer,
            records: [try Self.record(peer, seq: 1)],
            signedRecords: [
                try Self.envelope(peer, seq: 1), try Self.envelope(peer, seq: 2), try Self.envelope(other, seq: 3),
            ]
        )
        // The unsigned seq 1 picks up its envelope, seq 2 is added, and the other peer's envelope is skipped.
        #expect(compPeer.records.map(\.sequenceNumber).sorted() == [1, 2])
        #expect(compPeer.signedRecords.count == 2)

        let copy = compPeer.copy()
        #expect(copy.records == compPeer.records)
        #expect(try copy.signedRecords.map { try $0.marshal() } == compPeer.signedRecords.map { try $0.marshal() })
    }

    // MARK: - RecordRepository defaults

    /// A store that only implements the original requirements, like stores written before 0.6.1.
    final class UnsignedRecordStore: RecordRepository, @unchecked Sendable {
        let loop = EmbeddedEventLoop()
        private let records = NIOLockedValueBox<[PeerRecord]>([])
        var stored: [PeerRecord] { records.withLockedValue { $0 } }

        func add(record: PeerRecord, on: EventLoop?) -> EventLoopFuture<Void> {
            records.withLockedValue { $0.append(record) }
            return loop.makeSucceededVoidFuture()
        }
        func getRecords(forPeer peer: PeerID, on: EventLoop?) -> EventLoopFuture<[PeerRecord]> {
            loop.makeSucceededFuture(records.withLockedValue { $0.filter { $0.peerID.id == peer.id } })
        }
        func getMostRecentRecord(forPeer peer: PeerID, on: EventLoop?) -> EventLoopFuture<PeerRecord?> {
            getRecords(forPeer: peer, on: on).map { $0.max { $0.sequenceNumber < $1.sequenceNumber } }
        }
        func trimRecords(forPeer peer: PeerID, on: EventLoop?) -> EventLoopFuture<Void> {
            loop.makeSucceededVoidFuture()
        }
        func removeRecords(forPeer peer: PeerID, on: EventLoop?) -> EventLoopFuture<Void> {
            loop.makeSucceededVoidFuture()
        }
    }

    @Test func defaultAddSignedRecordStoresTheRecord() async throws {
        let store = UnsignedRecordStore()
        let peer = try PeerID(.Ed25519)

        try await store.add(signedRecord: Self.envelope(peer, seq: 4))

        #expect(store.stored.map(\.sequenceNumber) == [4])
        #expect(try await store.getMostRecentSignedRecord(forPeer: peer) == nil)
    }

    @Test func defaultAddSignedRecordFailsForAnInvalidRecord() async throws {
        let store = UnsignedRecordStore()
        let signer = try PeerID(.Ed25519)
        let envelope = try Self.envelope(signedBy: signer, naming: try PeerID(.Ed25519))

        await #expect(throws: (any Error).self) { try await store.add(signedRecord: envelope) }
        #expect(store.stored.isEmpty)
    }
}
