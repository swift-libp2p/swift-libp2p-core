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

import LibP2PCrypto
public import Multiaddr
public import NIOCore
public import PeerID

public enum RoutingErrors: Error, Sendable {
    /// ErrNotFound is returned when the router fails to find the requested record.
    case notFound
    /// ErrNotSupported is returned when the router doesn't support the given record type/operation.
    case notSupported
}

/// ContentRouting is a value provider layer of indirection. It is used to find information about who has what content.
///
/// Content is identified by CID (content identifier), which encodes a hash of the identified content in a future-proof manner.
public protocol ContentRouting {
    /// Provide adds the given cid to the content routing system. If 'true' is
    /// passed, it also announces it, otherwise it is just kept in the local
    /// accounting of which objects are being provided.
    func provide(cid: [UInt8], announce: Bool) -> EventLoopFuture<Void>

    /// Search for peers who are able to provide a given key
    ///
    /// - Note: When count is 0, this method will return an unbounded number of results.
    func findProviders(cid: [UInt8], count: Int) -> EventLoopFuture<[Multiaddr]>
}

/// PeerRouting is a way to find address information about certain peers.
///
/// This can be implemented by a simple lookup table, a tracking server, or even a DHT.
public protocol PeerRouting {
    // FindPeer searches for a peer with given ID, returns a peer.AddrInfo with relevant addresses.
    func findPeer(peer: PeerID) -> EventLoopFuture<PeerInfo>
}

/// ValueStore is a basic Put/Get interface.
public protocol ValueStore {
    /// putValue adds value corresponding to given Key.
    func putValue(key: String, value: [UInt8], options: [Any]) -> EventLoopFuture<Void>

    /// getValue searches for the value corresponding to the given key
    func getValue(key: String, options: [Any]) -> EventLoopFuture<[UInt8]>

    /// SearchValue searches for better and better values from this value store corresponding to the given Key.
    ///
    /// - Note: By default implementations must stop the search after a good value is found.
    /// A 'good' value is a value that would be returned from getValue.
    ///
    /// - Note: Useful when you want a result *now* but still want to hear about
    /// better/newer results.
    ///
    /// - Warning: Implementations of this methods won't return `Errors.notFound` When a value
    /// couldn't be found, the channel will get closed without passing any results
    ///
    /// - TODO: Not entirely sure if the escaping callback with a final eventloopfuture is the correct way to go about this.
    /// We want to simulate Combine's publish subcribe model, where we can listen for multiple events before the channel is closed.
    func searchValue(key: String, onValue: @escaping ([UInt8]) -> Void, options: [Any]) -> EventLoopFuture<[UInt8]>
}

extension ValueStore {
    /// putValue adds value corresponding to given Key.
    public func putValue(key: String, value: [UInt8]) -> EventLoopFuture<Void> {
        self.putValue(key: key, value: value, options: [])
    }

    /// getValue searches for the value corresponding to the given key.
    public func getValue(key: String) -> EventLoopFuture<[UInt8]> {
        self.getValue(key: key, options: [])
    }

    /// SearchValue searches for better and better values from this value store corresponding to the given Key.
    public func searchValue(key: String, onValue: @escaping ([UInt8]) -> Void) -> EventLoopFuture<[UInt8]> {
        self.searchValue(key: key, onValue: onValue, options: [])
    }
}

public protocol Routing: ContentRouting, PeerRouting, ValueStore {
    func bootstrap() -> EventLoopFuture<Void>
}

public protocol PublicKeyFetcher {
    // Takes a b58 or cid string and attempts to find the peers public key
    func getPublicKey(peerID: String) -> EventLoopFuture<PeerID>
}

internal enum _Routing {
    static let PublicKeyNamespace = [UInt8]("/pk/".utf8)

    static func keyForPublicKey(id: PeerID) -> String {
        "/pk/" + id.b58String
    }

    static func getPublicKey(_ store: ValueStore, peer: PeerID, on: EventLoop) -> EventLoopFuture<PeerID> {
        /// If the PeerID has a public key, just return it
        if peer.keyPair?.publicKey != nil {
            return on.makeSucceededFuture(peer)
        }

        /// If we have a DHT as our routing system, use optimized fetcher
        if let dht = store as? PublicKeyFetcher {
            return dht.getPublicKey(peerID: peer.cidString)
        }

        /// TODO: Implement ValueStore protocol ...
        return on.makeFailedFuture(RoutingErrors.notFound)

        //let key = keyForPublicKey(id: peer)
        //return store.getValue(key: key).flatMapThrowing { pkval -> PublicKey in
        //    try PublicKey(fromMarshaledValue: pkval)
        //}
    }
}

// MARK: - Async

extension ContentRouting {
    public func provide(cid: [UInt8], announce: Bool) async throws {
        try await self.provide(cid: cid, announce: announce).get()
    }

    public func findProviders(cid: [UInt8], count: Int) async throws -> [Multiaddr] {
        try await self.findProviders(cid: cid, count: count).get()
    }
}

extension PeerRouting {
    public func findPeer(peer: PeerID) async throws -> PeerInfo {
        try await self.findPeer(peer: peer).get()
    }
}

extension ValueStore {
    /// putValue adds the value under the given Key.
    public func putValue(key: String, value: [UInt8], options: [Any] = []) async throws {
        try await self.putValue(key: key, value: value, options: options).get()
    }

    /// getValue searches for the value corresponding to the given key.
    public func getValue(key: String, options: [Any] = []) async throws -> [UInt8] {
        try await self.getValue(key: key, options: options).get()
    }

    /// SearchValue searches for better values from this value store corresponding to the given Key.
    ///
    /// `onValue` is invoked for each intermediate value discovered, the returned value is the
    /// final, best value (the one `getValue` would return).
    public func searchValue(
        key: String,
        onValue: @escaping ([UInt8]) -> Void,
        options: [Any] = []
    ) async throws -> [UInt8] {
        try await self.searchValue(key: key, onValue: onValue, options: options).get()
    }
}

extension Routing {
    public func bootstrap() async throws {
        try await self.bootstrap().get()
    }
}

extension PublicKeyFetcher {
    public func getPublicKey(peerID: String) async throws -> PeerID {
        try await self.getPublicKey(peerID: peerID).get()
    }
}
