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

public protocol KeyRepository {
    func removeAllKeys(on: EventLoop?) -> EventLoopFuture<Void>
    func add(key: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func remove(key: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func getKey(forPeer: String, on: EventLoop?) -> EventLoopFuture<PeerID>
}

extension KeyRepository {
    public func removeAllKeys() -> EventLoopFuture<Void> {
        removeAllKeys(on: nil)
    }
    public func add(key: PeerID) -> EventLoopFuture<Void> {
        add(key: key, on: nil)
    }
    public func remove(key: PeerID) -> EventLoopFuture<Void> {
        remove(key: key, on: nil)
    }
    public func getKey(forPeer: String) -> EventLoopFuture<PeerID> {
        getKey(forPeer: forPeer, on: nil)
    }
}

// MARK: - Async

extension KeyRepository {
    public func removeAllKeys() async throws {
        try await self.removeAllKeys(on: nil).get()
    }

    public func add(key: PeerID) async throws {
        try await self.add(key: key, on: nil).get()
    }

    public func remove(key: PeerID) async throws {
        try await self.remove(key: key, on: nil).get()
    }

    public func getKey(forPeer: String) async throws -> PeerID {
        try await self.getKey(forPeer: forPeer, on: nil).get()
    }
}
