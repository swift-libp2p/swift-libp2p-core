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

public protocol ProtocolRepository {
    func removeAllProtocols(forPeer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func add(protocol: SemVerProtocol, toPeer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func add(protocols: [SemVerProtocol], toPeer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func remove(protocol: SemVerProtocol, fromPeer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func remove(protocols: [SemVerProtocol], fromPeer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func getProtocols(forPeer: PeerID, on: EventLoop?) -> EventLoopFuture<[SemVerProtocol]>
    func getPeers(supportingProtocol: SemVerProtocol, on: EventLoop?) -> EventLoopFuture<[String]>  //PeerID
}

extension ProtocolRepository {
    public func removeAllProtocols(forPeer: PeerID) -> EventLoopFuture<Void> {
        removeAllProtocols(forPeer: forPeer, on: nil)
    }
    public func add(protocol proto: SemVerProtocol, toPeer: PeerID) -> EventLoopFuture<Void> {
        add(protocol: proto, toPeer: toPeer, on: nil)
    }
    public func add(protocols: [SemVerProtocol], toPeer: PeerID) -> EventLoopFuture<Void> {
        add(protocols: protocols, toPeer: toPeer, on: nil)
    }
    public func remove(protocol proto: SemVerProtocol, fromPeer: PeerID) -> EventLoopFuture<Void> {
        remove(protocol: proto, fromPeer: fromPeer, on: nil)
    }
    public func remove(protocols: [SemVerProtocol], fromPeer: PeerID) -> EventLoopFuture<Void> {
        remove(protocols: protocols, fromPeer: fromPeer, on: nil)
    }
    public func getProtocols(forPeer: PeerID) -> EventLoopFuture<[SemVerProtocol]> {
        getProtocols(forPeer: forPeer, on: nil)
    }
    public func getPeers(supportingProtocol: SemVerProtocol) -> EventLoopFuture<[String]> {
        getPeers(supportingProtocol: supportingProtocol, on: nil)
    }
}

// MARK: - Async

extension ProtocolRepository {
    public func removeAllProtocols(forPeer: PeerID) async throws {
        try await self.removeAllProtocols(forPeer: forPeer, on: nil).get()
    }

    public func add(protocol proto: SemVerProtocol, toPeer: PeerID) async throws {
        try await self.add(protocol: proto, toPeer: toPeer, on: nil).get()
    }

    public func add(protocols: [SemVerProtocol], toPeer: PeerID) async throws {
        try await self.add(protocols: protocols, toPeer: toPeer, on: nil).get()
    }

    public func remove(protocol proto: SemVerProtocol, fromPeer: PeerID) async throws {
        try await self.remove(protocol: proto, fromPeer: fromPeer, on: nil).get()
    }

    public func remove(protocols: [SemVerProtocol], fromPeer: PeerID) async throws {
        try await self.remove(protocols: protocols, fromPeer: fromPeer, on: nil).get()
    }

    public func getProtocols(forPeer: PeerID) async throws -> [SemVerProtocol] {
        try await self.getProtocols(forPeer: forPeer, on: nil).get()
    }

    public func getPeers(supportingProtocol: SemVerProtocol) async throws -> [String] {
        try await self.getPeers(supportingProtocol: supportingProtocol, on: nil).get()
    }
}
