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

public protocol AddressRepository: Sendable {
    /// - TODO: These operations should emit `onAddressAdded` / `onAddressRemoved` events once the
    ///   peerstore is wired into the `EventBus`. Nothing emits them today.

    func add(address: Multiaddr, toPeer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func add(addresses: [Multiaddr], toPeer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func remove(address: Multiaddr, fromPeer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func removeAllAddresses(forPeer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func getAddresses(forPeer: PeerID, on: EventLoop?) -> EventLoopFuture<[Multiaddr]>
    func getPeer(byAddress: Multiaddr, on: EventLoop?) -> EventLoopFuture<String>
    func getPeerID(byAddress address: Multiaddr, on: EventLoop?) -> EventLoopFuture<PeerID>
    func getPeerInfo(byAddress address: Multiaddr, on: EventLoop?) -> EventLoopFuture<PeerInfo>
}

extension AddressRepository {
    public func add(address: Multiaddr, toPeer: PeerID) -> EventLoopFuture<Void> {
        add(address: address, toPeer: toPeer, on: nil)
    }
    public func add(addresses: [Multiaddr], toPeer: PeerID) -> EventLoopFuture<Void> {
        add(addresses: addresses, toPeer: toPeer, on: nil)
    }
    public func remove(address: Multiaddr, fromPeer: PeerID) -> EventLoopFuture<Void> {
        remove(address: address, fromPeer: fromPeer, on: nil)
    }
    public func removeAllAddresses(forPeer: PeerID) -> EventLoopFuture<Void> {
        removeAllAddresses(forPeer: forPeer, on: nil)
    }
    public func getAddresses(forPeer: PeerID) -> EventLoopFuture<[Multiaddr]> {
        getAddresses(forPeer: forPeer, on: nil)
    }
    public func getPeer(byAddress: Multiaddr) -> EventLoopFuture<String> {
        getPeer(byAddress: byAddress, on: nil)
    }
    public func getPeerID(byAddress address: Multiaddr) -> EventLoopFuture<PeerID> {
        getPeerID(byAddress: address, on: nil)
    }
    public func getPeerInfo(byAddress address: Multiaddr) -> EventLoopFuture<PeerInfo> {
        getPeerInfo(byAddress: address, on: nil)
    }
}

// MARK: - Async

extension AddressRepository {
    public func add(address: Multiaddr, toPeer: PeerID) async throws {
        try await self.add(address: address, toPeer: toPeer, on: nil).get()
    }

    public func add(addresses: [Multiaddr], toPeer: PeerID) async throws {
        try await self.add(addresses: addresses, toPeer: toPeer, on: nil).get()
    }

    public func remove(address: Multiaddr, fromPeer: PeerID) async throws {
        try await self.remove(address: address, fromPeer: fromPeer, on: nil).get()
    }

    public func removeAllAddresses(forPeer: PeerID) async throws {
        try await self.removeAllAddresses(forPeer: forPeer, on: nil).get()
    }

    public func getAddresses(forPeer: PeerID) async throws -> [Multiaddr] {
        try await self.getAddresses(forPeer: forPeer, on: nil).get()
    }

    public func getPeer(byAddress: Multiaddr) async throws -> String {
        try await self.getPeer(byAddress: byAddress, on: nil).get()
    }

    public func getPeerID(byAddress address: Multiaddr) async throws -> PeerID {
        try await self.getPeerID(byAddress: address, on: nil).get()
    }

    public func getPeerInfo(byAddress address: Multiaddr) async throws -> PeerInfo {
        try await self.getPeerInfo(byAddress: address, on: nil).get()
    }
}
