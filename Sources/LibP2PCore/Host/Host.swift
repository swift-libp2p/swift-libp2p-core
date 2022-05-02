//
//  Host.swift
//  
//
//  Created by Brandon Toms on 3/8/22.
//

import NIOCore
import PeerID
import Multiaddr

/// Host is an object participating in a p2p network, which
/// implements protocols or provides services. It handles
/// requests like a Server, and issues requests like a Client.
/// It is called Host because it is both Server and Client (and Peer
/// may be confusing).
protocol Host {
    /// ID returns the (local) peer.ID associated with this Host
    var ID:PeerID { get }

    /// Peerstore returns the Host's repository of Peer Addresses and Keys.
    var peerstore:PeerStore { get }

    /// Returns the listen addresses of the Host
    var listeningAddresses:[Multiaddr] { get }

    /// Networks returns the Network interface of the Host
    var network:Network { get }

    /// Mux returns the Mux multiplexing incoming streams to protocol handlers
    var mux:[Muxer] { get }

    /// Connect ensures there is a connection between this host and the peer with
    /// given peer.ID. Connect will absorb the addresses in pi into its internal
    /// peerstore. If there is not an active connection, Connect will issue a
    /// h.Network.Dial, and block until a connection is open, or an error is
    /// returned. // TODO: Relay + NAT.
    func connect(peer:PeerInfo) -> EventLoopFuture<Void>

    /// SetStreamHandler sets the protocol handler on the Host's Mux.
    /// This is equivalent to:
    ///   host.Mux().SetHandler(proto, handler)
    /// (Threadsafe)
//    func setStreamHandler(pid protocol.ID, handler network.StreamHandler)

    /// SetStreamHandlerMatch sets the protocol handler on the Host's Mux
    /// using a matching function for protocol selection.
//    func setStreamHandlerMatch(protocol.ID, func(string) bool, network.StreamHandler)

    /// RemoveStreamHandler removes a handler on the mux that was set by
    /// SetStreamHandler
//    func removeStreamHandler(pid protocol.ID)

    /// NewStream opens a new stream to given peer p, and writes a p2p/protocol
    /// header with given ProtocolID. If there is no connection to p, attempts
    /// to create one. If ProtocolID is "", writes no header.
    /// (Threadsafe)
    func newStream(_ peer:PeerID) -> EventLoopFuture<Stream>

    /// Close shuts down the host, its Network, and services.
    func close() -> EventLoopFuture<Void>

    /// ConnManager returns this hosts connection manager
    var connManager: ConnectionManager { get }

    /// EventBus returns the hosts eventbus
    var eventBus: EventBus { get }
}

