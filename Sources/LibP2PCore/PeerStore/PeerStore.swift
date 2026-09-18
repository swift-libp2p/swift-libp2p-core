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
import NIOConcurrencyHelpers
public import NIOCore

public protocol PeerStore: KeyRepository, AddressRepository, ProtocolRepository, MetadataRepository, RecordRepository,
    Sendable
{
    /// Returns a collection of every peer in the PeerStore
    ///
    /// - Warning: This can be slow and resource heavy if the peerstore contains a large
    ///   number of peers.
    func all() -> EventLoopFuture<[ComprehensivePeer]>

    /// Returns the number of Peers that are currently stored in the PeerStore
    func count() -> EventLoopFuture<Int>

    /// Logs the specified peer to the console
    ///
    /// Debug utility: A default implementation is provided, conformers do not need to
    /// implement this.
    func dump(peer: PeerID)

    /// Logs the entire PeerStore to the console
    ///
    /// Debug utility: A default implementation is provided, conformers do not need to
    /// implement this.
    func dumpAll()

    /// Every `PeerID` currently held by the store.
    func getAllPeerIDs(on: EventLoop?) -> EventLoopFuture<[PeerID]>

    /// Every peer currently held by the store, paired with their known addresses.
    func getAllPeerInfos(on: EventLoop?) -> EventLoopFuture<[PeerInfo]>

    /// The `PeerID`s of every peer known to support `supportingProtocol` **exactly**.
    func getPeerIDs(supportingProtocol: SemVerProtocol, on: EventLoop?) -> EventLoopFuture<[PeerID]>

    /// The b58 identifiers of every peer supporting a protocol *compatible* with
    /// `matchingProtocol`, using ``SemVerProtocol/matches(_:)`` semantics.
    func getPeers(matchingProtocol: SemVerProtocol, on: EventLoop?) -> EventLoopFuture<[String]>

    /// The `PeerID`s of every peer supporting a protocol *compatible* with
    /// `matchingProtocol`,  using ``SemVerProtocol/matches(_:)`` semantics.
    func getPeerIDs(matchingProtocol: SemVerProtocol, on: EventLoop?) -> EventLoopFuture<[PeerID]>
}

extension PeerStore {

    /// Logs the specified peer to the console once the lookup completes.
    public func dump(peer: PeerID) {
        self.all().whenSuccess { peers in
            guard let match = peers.first(where: { $0.id == peer }) else { return }
            print(match.description)
        }
    }

    /// Logs the entire PeerStore to the console once the lookup completes.
    public func dumpAll() {
        self.all().whenSuccess { peers in
            for peer in peers {
                print(peer.description)
            }
        }
    }

    /// Given a `PeerInfo` object this method adds both the `PeerID` and the associated `Multiaddr`s to the `PeerStore`.
    /// - Parameters:
    ///   - peerInfo: the `PeerInfo` object to store
    ///   - on: An optional `EventLoop` to return on
    /// - Returns: `Void` upon success, or error upon failure
    public func add(peerInfo: PeerInfo, on: EventLoop? = nil) -> EventLoopFuture<Void> {
        self.add(key: peerInfo.peer, on: on).flatMap {
            self.add(addresses: peerInfo.addresses, toPeer: peerInfo.peer, on: on)
        }
    }

    /// Given a `PeerInfo` object this method adds both the `PeerID` and the associated `Multiaddr`s to the `PeerStore`.
    /// - Parameters:
    ///   - peerInfo: the `PeerInfo` object to store
    ///   - on: An optional `EventLoop` to return on
    /// - Returns: `Void` upon success, or error upon failure
    public func add(peerInfo: PeerInfo, on: EventLoop? = nil) async throws {
        try await self.add(peerInfo: peerInfo, on: on).get()
    }

    public func getPeerInfo(byID id: String, on: EventLoop? = nil) -> EventLoopFuture<PeerInfo> {
        self.getKey(forPeer: id, on: on).flatMap { key in
            self.getAddresses(forPeer: key, on: on).map { addresses in
                PeerInfo(peer: key, addresses: addresses)
            }
        }
    }

    public func getPeerInfo(byID id: String, on: EventLoop? = nil) async throws -> PeerInfo {
        try await self.getPeerInfo(byID: id, on: on).get()
    }

    public func getAllPeerIDs(on: EventLoop?) -> EventLoopFuture<[PeerID]> {
        self.all().map { peers in peers.map { $0.id } }.hopIfNeeded(to: on)
    }

    public func getAllPeerIDs() -> EventLoopFuture<[PeerID]> {
        self.getAllPeerIDs(on: nil)
    }

    public func getAllPeerInfos(on: EventLoop?) -> EventLoopFuture<[PeerInfo]> {
        self.all().map { peers in peers.map { $0.peerInfo } }.hopIfNeeded(to: on)
    }

    public func getAllPeerInfos() -> EventLoopFuture<[PeerInfo]> {
        self.getAllPeerInfos(on: nil)
    }

    public func getPeerIDs(supportingProtocol proto: SemVerProtocol, on: EventLoop?) -> EventLoopFuture<[PeerID]> {
        self.all().map { peers in
            peers.filter { $0.protocols.contains(proto) }.map { $0.id }
        }.hopIfNeeded(to: on)
    }

    public func getPeerIDs(supportingProtocol proto: SemVerProtocol) -> EventLoopFuture<[PeerID]> {
        self.getPeerIDs(supportingProtocol: proto, on: nil)
    }

    public func getPeers(matchingProtocol proto: SemVerProtocol, on: EventLoop?) -> EventLoopFuture<[String]> {
        self.all().map { peers in
            peers.filter { $0.protocols.contains { $0.matches(proto) } }.map { $0.id.b58String }
        }.hopIfNeeded(to: on)
    }

    public func getPeers(matchingProtocol proto: SemVerProtocol) -> EventLoopFuture<[String]> {
        self.getPeers(matchingProtocol: proto, on: nil)
    }

    public func getPeerIDs(matchingProtocol proto: SemVerProtocol, on: EventLoop?) -> EventLoopFuture<[PeerID]> {
        self.all().map { peers in
            peers.filter { $0.protocols.contains { $0.matches(proto) } }.map { $0.id }
        }.hopIfNeeded(to: on)
    }

    public func getPeerIDs(matchingProtocol proto: SemVerProtocol) -> EventLoopFuture<[PeerID]> {
        self.getPeerIDs(matchingProtocol: proto, on: nil)
    }
}

extension EventLoopFuture {
    /// `hop(to:)` when a destination loop was supplied, otherwise a no-op.
    internal func hopIfNeeded(to eventLoop: EventLoop?) -> EventLoopFuture<Value> {
        guard let eventLoop else { return self }
        return self.hop(to: eventLoop)
    }
}

// MARK: - Async

extension PeerStore {
    public func all() async throws -> [ComprehensivePeer] {
        try await self.all().get()
    }

    public func count() async throws -> Int {
        try await self.count().get()
    }

    public func getAllPeerIDs() async throws -> [PeerID] {
        try await self.getAllPeerIDs(on: nil).get()
    }

    public func getAllPeerInfos() async throws -> [PeerInfo] {
        try await self.getAllPeerInfos(on: nil).get()
    }

    public func getPeerIDs(supportingProtocol proto: SemVerProtocol) async throws -> [PeerID] {
        try await self.getPeerIDs(supportingProtocol: proto, on: nil).get()
    }

    public func getPeers(matchingProtocol proto: SemVerProtocol) async throws -> [String] {
        try await self.getPeers(matchingProtocol: proto, on: nil).get()
    }

    public func getPeerIDs(matchingProtocol proto: SemVerProtocol) async throws -> [PeerID] {
        try await self.getPeerIDs(matchingProtocol: proto, on: nil).get()
    }
}
