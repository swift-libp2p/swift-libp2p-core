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

public protocol RecordRepository: Sendable {

    /// Adds an unsigned (or local) record. Prefer ``add(signedRecord:on:)`` for records received from peers.
    func add(record: PeerRecord, on: EventLoop?) -> EventLoopFuture<Void>

    /// Returns the stored PeerRecords for the given PeerID
    func getRecords(forPeer peer: PeerID, on: EventLoop?) -> EventLoopFuture<[PeerRecord]>

    /// Returns the most recent PeerRecord (by sequence number) for the given PeerID
    func getMostRecentRecord(forPeer peer: PeerID, on: EventLoop?) -> EventLoopFuture<PeerRecord?>

    /// Removes all the but the configured max amount of Records for the given PeerID
    func trimRecords(forPeer peer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>

    /// Removes all Records for the given PeerID
    func removeRecords(forPeer peer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>

    /// Adds the `PeerRecord` carried by a verified envelope, keeping the envelope so it can be handed
    /// out exactly as the peer signed it (e.g. for gossipsub peer exchange).
    ///
    /// - Note: Implementations should store the record as ``add(record:on:)`` does (including merging its
    /// addresses) and keep the envelope alongside it.
    func add(signedRecord envelope: SealedEnvelope, on: EventLoop?) -> EventLoopFuture<Void>

    /// The envelope of the most recent record that arrived signed, exactly as the peer signed it.
    func getMostRecentSignedRecord(forPeer peer: PeerID, on: EventLoop?) -> EventLoopFuture<SealedEnvelope?>
}

// TODO: Remove / rework these signatures in 0.7.0
extension RecordRepository {
    /// Stores the envelope's record via ``add(record:on:)``, dropping the envelope.
    public func add(signedRecord envelope: SealedEnvelope, on: EventLoop?) -> EventLoopFuture<Void> {
        let record: PeerRecord
        do {
            record = try PeerRecord(signedEnvelope: envelope)
        } catch {
            /// because eventloop is optional lets piggy back off of an actual call
            return self.getRecords(forPeer: envelope.pubKey, on: on).flatMapThrowing { _ in throw error }
        }
        return self.add(record: record, on: on)
    }

    /// Returns `nil`
    public func getMostRecentSignedRecord(forPeer peer: PeerID, on: EventLoop?) -> EventLoopFuture<SealedEnvelope?> {
        /// because eventloop is optional lets piggy back off of an actual call
        self.getRecords(forPeer: peer, on: on).map { _ in nil }
    }
}

extension RecordRepository {
    public func add(signedRecord envelope: SealedEnvelope) -> EventLoopFuture<Void> {
        add(signedRecord: envelope, on: nil)
    }
    public func getMostRecentSignedRecord(forPeer peer: PeerID) -> EventLoopFuture<SealedEnvelope?> {
        getMostRecentSignedRecord(forPeer: peer, on: nil)
    }
}

extension RecordRepository {
    public func add(record: PeerRecord) -> EventLoopFuture<Void> {
        add(record: record, on: nil)
    }
    public func getRecords(forPeer peer: PeerID) -> EventLoopFuture<[PeerRecord]> {
        getRecords(forPeer: peer, on: nil)
    }
    public func getMostRecentRecord(forPeer peer: PeerID) -> EventLoopFuture<PeerRecord?> {
        getMostRecentRecord(forPeer: peer, on: nil)
    }
    public func trimRecords(forPeer peer: PeerID) -> EventLoopFuture<Void> {
        trimRecords(forPeer: peer, on: nil)
    }
    public func removeRecords(forPeer peer: PeerID) -> EventLoopFuture<Void> {
        removeRecords(forPeer: peer, on: nil)
    }
}

// MARK: - Async

extension RecordRepository {
    public func add(record: PeerRecord) async throws {
        try await self.add(record: record, on: nil).get()
    }

    public func getRecords(forPeer peer: PeerID) async throws -> [PeerRecord] {
        try await self.getRecords(forPeer: peer, on: nil).get()
    }

    public func getMostRecentRecord(forPeer peer: PeerID) async throws -> PeerRecord? {
        try await self.getMostRecentRecord(forPeer: peer, on: nil).get()
    }

    public func trimRecords(forPeer peer: PeerID) async throws {
        try await self.trimRecords(forPeer: peer, on: nil).get()
    }

    public func removeRecords(forPeer peer: PeerID) async throws {
        try await self.removeRecords(forPeer: peer, on: nil).get()
    }

    public func add(signedRecord envelope: SealedEnvelope) async throws {
        try await self.add(signedRecord: envelope, on: nil).get()
    }

    public func getMostRecentSignedRecord(forPeer peer: PeerID) async throws -> SealedEnvelope? {
        try await self.getMostRecentSignedRecord(forPeer: peer, on: nil).get()
    }
}
