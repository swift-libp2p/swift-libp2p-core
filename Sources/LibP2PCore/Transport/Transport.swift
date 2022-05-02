//
//  Transport.swift
//  
//
//  Created by Brandon Toms on 3/8/22.
//

import NIOCore
import PeerID
import Multiaddr

/// A CapableConn represents a connection that offers the basic
/// capabilities required by libp2p: stream multiplexing, encryption and
/// peer authentication.
///
/// These capabilities may be natively provided by the transport, or they
/// may be shimmed via the "connection upgrade" process, which converts a
/// "raw" network connection into one that supports such capabilities by
/// layering an encryption channel and a stream multiplexer.
///
/// CapableConn provides accessors for the local and remote multiaddrs used to
/// establish the connection and an accessor for the underlying Transport.
public protocol CapableConnection: Connection {
    var muxer:Muxer { get }
    var security:Security { get }
    var remoteAddress:Multiaddr { get }
    var localAddress:Multiaddr { get }
    //var scoper:Connection.Scoper { get }
    
    /// transport returns the Transport to which this connection belongs
    var transport:Transport { get }
}

public protocol TransportManager {
    //func getAll(on:EventLoop?) -> EventLoopFuture<[Transport]>
    //func clear(on:EventLoop?) -> EventLoopFuture<Void>
    //func findBest(forMultiaddr:Multiaddr, on:EventLoop?) -> EventLoopFuture<Transport>
    
    func getAll() -> [Transport]
    func findBest(forMultiaddr:Multiaddr) throws -> Transport
}

/// This can be a placeholder for implementations to register their keys / configs on.
public enum TransportConfig {  }

/// Transport represents any device by which you can connect to and accept
/// connections from other peers.
///
/// The Transport interface allows you to open connections to other peers
/// by dialing them, and also lets you listen for incoming connections.
///
/// Connections returned by Dial and passed into Listeners are of type
/// CapableConn, which means that they have been upgraded to support
/// stream multiplexing and connection security (encryption and authentication).
///
/// If a transport implements `io.Closer` (optional), libp2p will call `Close` on
/// shutdown. NOTE: `Dial` and `Listen` may be called after or concurrently with
/// `Close`.
///
/// For a conceptual overview, see https://docs.libp2p.io/concepts/transport/
public protocol Transport:CustomStringConvertible {
    /// The transports Uniqe key descriptor
    static var key:String { get }
    
    /// Dial dials a remote peer. It should try to reuse local listener addresses if possible but it may choose not to.
    /// TODO: Return a CapableConnection??
    func dial(address:Multiaddr) -> EventLoopFuture<Connection>
    
    /// CanDial returns true if this transport knows how to dial the given multiaddr.
    ///
    /// Returning true does not guarantee that dialing this multiaddr will
    /// succeed. This function should *only* be used to preemptively filter
    /// out addresses that we can't dial.
    func canDial(address:Multiaddr) -> Bool
    
    /// Listen listens on the passed multiaddr.
    func listen(address:Multiaddr) -> EventLoopFuture<Listener>
    
    /// Protocol returns the set of protocols handled by this transport.
    var protocols:[LibP2PProtocol] { get }
    
    /// returns true if this is a proxy transport
    var proxy:Bool { get }
}

/// Listener is an interface closely resembling the net.Listener interface.
///
/// - Note: The only real difference is that `accept()` returns Connections of the type in this package, and also exposes a Multiaddr method as opposed to a regular Addr method
public protocol Listener {
    func accept() -> EventLoopFuture<Connection>
    func close() -> EventLoopFuture<Void>
    
    var address:Multiaddr { get }
}

/// TransportNetwork is an inet.Network with methods for managing transports.
public protocol TransportNetwork {
    var network:Network { get }
    
    /// AddTransport adds a transport to this Network.
    ///
    /// When dialing, this Network will iterate over the protocols in the
    /// remote multiaddr and pick the first protocol registered with a proxy
    /// transport, if any. Otherwise, it'll pick the transport registered to
    /// handle the last protocol in the multiaddr.
    ///
    /// When listening, this Network will iterate over the protocols in the
    /// local multiaddr and pick the *last* protocol registered with a proxy
    /// transport, if any. Otherwise, it'll pick the transport registered to
    /// handle the last protocol in the multiaddr.
    func addTransport(_ t:Transport) -> EventLoopFuture<Void>
}

/// Upgrader is a multistream upgrader that can upgrade an underlying connection to a full transport connection (secure and multiplexed).
public protocol Upgrader {
    //func upgradeListener(_ t:Transport, listener:MAListener) -> EventLoopFuture<Listener>
    
    //func upgrade(_ t:Transport, maconn:MAConnection, direction:Network.Direction, peer:Peer, scope:ConnectionManager.Scope) -> EventLoopFuture<CapableConnection>
}

extension Transport {
    public var description:String {
        return "\(Self.key)"
    }
}
