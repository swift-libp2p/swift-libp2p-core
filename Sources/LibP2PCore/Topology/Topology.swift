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

import NIOCore
import PeerID

/// Taps into the current pool of connections and can filter connections / disconnection events to interested parties / subscribers
public protocol Topology {

    //init(min:Int, max:Int, handlers:TopologyHandler)

    var min: Int { get }

    var max: Int { get }

    /// An optional Object containing the handler called when a peer is connected or disconnected
    var handlers: TopologyHandler { get }

    /// A Map of peers belonging to the topology.
    var peers: [String: PeerID] { get }

    /// Add a peer to the topology.
    func set(id: String, peer: PeerID) -> EventLoopFuture<Bool>?

    /// Disconnects a peer from the topology.
    func disconnect(peer: PeerID) -> EventLoopFuture<Void>?

    func deinitialize()
}

/// An optional Object containing the handler called when a peer is connected or disconnected
public struct TopologyHandler: Sendable {
    /// called everytime a peer is connected in the topology context.
    public let onConnect: @Sendable (PeerID, Connection) -> Void

    public let onNewStream: (@Sendable (Stream) -> Void)?

    /// called everytime a peer is disconnected in the topology context.
    public let onDisconnect: (@Sendable (PeerID) -> Void)?

    public init(
        onConnect: @escaping (@Sendable (PeerID, Connection) -> Void),
        onNewStream: (@Sendable (Stream) -> Void)? = nil,
        onDisconnect: (@Sendable (PeerID) -> Void)? = nil
    ) {
        self.onConnect = onConnect
        self.onNewStream = onNewStream
        self.onDisconnect = onDisconnect
    }
}

public protocol MulticodecTopology: Topology {
    /// Creates a new Multicodec Topology, that aggregates, and notifies you of, connected peers that support the specified protocols
    init(min: Int, max: Int, handlers: TopologyHandler, protocols: [SemVerProtocol])
    /// The multicodecs (aka protocols) this topology is interested in
    var protocols: [SemVerProtocol] { get }
}
