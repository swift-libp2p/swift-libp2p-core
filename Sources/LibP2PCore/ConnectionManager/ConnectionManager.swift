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

/// - TODO: Remove Optional Return Value
public protocol ConnectionManager: Sendable {
    func getConnections(on: EventLoop?) -> EventLoopFuture<[Connection]>
    func getConnectionsToPeer(peer: PeerID, on: EventLoop?) -> EventLoopFuture<[Connection]>
    func getBestConnectionForPeer(peer: PeerID, on: EventLoop?) -> EventLoopFuture<Connection?>
    func connectedness(peer: PeerID, on: EventLoop?) -> EventLoopFuture<Connectedness>
    /// Does this need a toPeer
    func addConnection(_: Connection, on: EventLoop?) -> EventLoopFuture<Void>
    //func addConnection(_:Connection, toPeer:PeerID, on:EventLoop) -> EventLoopFuture<Void>
    func closeConnectionsToPeer(peer: PeerID, on: EventLoop?) -> EventLoopFuture<Bool>

    func getConnectionsTo(_: Multiaddr, onlyMuxed: Bool, on: EventLoop?) -> EventLoopFuture<[Connection]>
    func closeAllConnections() -> EventLoopFuture<Void>

    //    func onNewInboundChannel(channel:Channel) -> EventLoopFuture<Void>
    //    func onNewOutboundChannel(channel:Channel, remoteAddress:Multiaddr) -> EventLoopFuture<Void>

    /// Prints the connection history
    func dumpConnectionHistory()

    /// Update the maximum simultaneuous Connections allowed
    func setMaxConnections(_: Int)

    /// Sets the Idle Timeout for Connections with zero streams
    func setIdleTimeout(_: TimeAmount)
}

/// Peer Connectedness
public enum Connectedness: Sendable {
    /// We have not yet attempted to connect to the peer in question
    case NotConnected
    /// We have an existing open connection to the peer in question
    case Connected
    /// We have previously connected to this peer, and can most likely connect to them again
    case CanConnect
    /// We have attempted to connect to this peer and we unable to establish a capcable connection
    case CanNotConnect
}
