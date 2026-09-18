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
    func add(record: PeerRecord, on: EventLoop?) -> EventLoopFuture<Void>
    func getRecords(forPeer peer: PeerID, on: EventLoop?) -> EventLoopFuture<[PeerRecord]>
    func getMostRecentRecord(forPeer peer: PeerID, on: EventLoop?) -> EventLoopFuture<PeerRecord?>
    func trimRecords(forPeer peer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func removeRecords(forPeer peer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
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
}
