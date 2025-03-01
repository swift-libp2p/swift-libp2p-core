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

import Multiaddr
import NIOCore
import PeerID

/// Advertiser is an interface for advertising services
public protocol Advertiser {
    /// Advertise advertises a service on the specified protocol and returns the registration TTL upon successful registration
    ///
    /// - TODO: Add in options
    func advertise(service: String, options: Options?) -> EventLoopFuture<TimeAmount>
}

/// Discoverer is an interface for peer discovery
public protocol Discoverer {
    /// FindPeers discovers peers providing a service
    ///
    /// - TODO: Add in options
    func findPeers(supportingService: String, options: Options?) -> EventLoopFuture<DiscoverdPeers>

    /// Allows LibP2P to register a callback / event handler on the Discovery mechanism to be alerted of various events, such as peer discovery.
    var onPeerDiscovered: ((_ peerInfo: PeerInfo) -> Void)? { get set }
}

/// Discovery is an interface that combines service advertisement and peer discovery
public protocol Discovery: Advertiser, Discoverer {
    static var key: String { get }
}

public protocol PeerDiscovery: EventLoopService {
    /// Allows LibP2P to register a callback / event handler on the Discovery mechanism to be alerted of various events, such as peer discovery.
    var on: ((_ event: PeerDiscoveryEvent) -> Void)? { get set }
    /// Allows LibP2P to query the Discovery mechanism for all of the peers it has encountered so far
    func knownPeers() -> EventLoopFuture<[PeerInfo]>
}

public protocol Options {
    /// TTL is an option that provides a hint for the duration of an advertisement
    var ttl: TimeAmount { get }
    /// Limit is an option that provides an upper bound on the peer count for discovery
    var limit: Int { get }
    /// Application specific options
    var other: [String: String]? { get }
}

extension Options {
    public var other: [String: String]? { nil }
}

public struct StandardOptions: Options {
    public var ttl: TimeAmount
    public var limit: Int
}

public struct DiscoverdPeers {
    public let cookie: Data?
    public let peers: [PeerInfo]

    public init(peers: [PeerInfo], cookie: Data? = nil) {
        self.peers = peers
        self.cookie = cookie
    }
}
