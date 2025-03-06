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

import Foundation
import Logging
import Multiaddr
import NIOCore
import PeerID

/// The connection interface contains all the metadata associated with it, as well as an array of the streams opened through this connection
///
/// - Libp2p Streams ≈ Swift NIO Channels
/// - Libp2p Connection ≈ Swift NIO Client (or maybe Libp2p Transport is more akin to the Client, and Channel is a parent wrapper that handles meta data surrounding the client, streams and peer)
///
/// [LibP2P Connection Interface Documentation](https://github.com/libp2p/js-libp2p-interfaces/tree/master/src/connection)
public protocol Connection: AnyObject {

    typealias NegotiationResult = (protocol: String, leftoverBytes: ByteBuffer?)
    typealias SecuredResult = (securityCodec: String, remotePeer: PeerID?, warning: SecurityWarnings?)

    /// Initializer for a new Connection
    //init(channel:Channel, localAddress:Multiaddr, remoteAddress:Multiaddr, localPeer:PeerID, remotePeer:PeerID, stats:ConnectionStats)

    //init(channel:Channel, localPeerID:PeerID, direction:ConnectionStats.Direction)

    var channel: Channel { get }

    /// the logger specific to this connection
    var logger: Logger { get }

    /// the identifier of the connection
    var id: UUID { get }

    /// The state of the connection (raw -> secured -> muxed -> upgraded)
    var state: ConnectionState { get }

    /// the local multiaddr address
    var localAddr: Multiaddr? { get }

    /// the remote multiaddr address
    var remoteAddr: Multiaddr? { get }

    /// the local peer-id of this connection
    var localPeer: PeerID { get }

    /// the remote peer-id of this connection
    var remotePeer: PeerID? { get }

    /// the metadata of the connection
    var stats: ConnectionStats { get }

    /// an array of tags associated with the connection. New tags can be pushed to this array during the connection's lifetime
    var tags: Any? { get }

    /// a map with the muxed streams indexed by their id. This registry contains the protocol used by the stream, as well as its metadata
    var registry: [UInt64: Stream] { get }

    /// all the muxed streams within the connection.
    /// Is a Stream a Channel in SwiftNIO? Is is a direct 1-1 comparison? Do we need to wrap a NIO Channel in a Stream Object that exposes a similar API?
    var streams: [Stream] { get }

    /// A reference to the muxer installed on the Connections underlying channel
    var muxer: Muxer? { get }

    /// A boolean indicating wether the Connection supports muxed streams or not
    var isMuxed: Bool { get }

    /// A convenience var to expose our Connections' current status
    var status: ConnectionStats.Status { get }

    /// A convenience var to expose our ConnectionStats timeline
    var timeline: [ConnectionStats.Status: Date] { get }

    /// A muxedChildChannelInitializer for new muxed streams
    //var muxedChildChannelInitializer:((Channel, Mode) -> EventLoopFuture<Void>) { get }

    func inboundMuxedChildChannelInitializer(_ childChannel: Channel) -> EventLoopFuture<Void>

    func outboundMuxedChildChannelInitializer(_ childChannel: Channel, protocol: String) -> EventLoopFuture<Void>

    /// Initializes the Connection Channel by installing the necessary Channel Handlers into the Channels Pipeline
    //func initializeChannel() -> EventLoopFuture<Void>

    /// Create a new stream within the connection.
    /// - Parameters:
    ///   - protos: an array of the intended protocol to use (by order of preference). Example: [/echo/1.0.0]
    ///   - completion: A result containing the new stream or an error on failure
    /// - TODO: MultiAddr.Protocol doesn't support versioning, we should extend/add this...
    func newStream(_ protos: [String]) -> EventLoopFuture<Stream>
    func newStreamSync(_ proto: String) throws -> Stream
    func newStreamHandlerSync(_ proto: String) throws -> StreamHandler
    func newStream(forProtocol: String)

    /// Removes the stream with the given id from the connection registry.
    ///
    /// - Parameter id: the unique id of the stream youd like to remove from this connection.
    func removeStream(id: UInt64) -> EventLoopFuture<Void>

    /// Add a new stream to the connection registry
    /// - Parameters:
    ///   - stream: a muxed stream
    ///   - protocol: the string codec for the protocol used by the stream (ex: /echo/1.0.0)
    ///   - metadata: an object containing any additional, optional, stream metadata that you wish to track (such as its tags)
    /// - TODO: MultiAddr.Protocol doesn't support versioning, we should extend/add this...
    func acceptStream(_ stream: Stream, protocol: String, metadata: [String]) -> EventLoopFuture<Bool>

    /// Check the connection for an existing stream for the specified protocol and optional direction.
    /// - Returns: The `Stream` if one was found, `nil` otherwise
    func hasStream(forProtocol: String, direction: ConnectionStats.Direction?) -> Stream?

    /// This method closes the connection to the remote peer, as well as all the streams muxed within the connection.
    /// - Parameter completion: Result indicating a successful closing of the connection or any relevant Errors that occured
    func close() -> EventLoopFuture<Void>
}

extension Connection {
    public var mode: LibP2PCore.Mode {
        switch self.stats.direction {
        case .inbound:
            return .listener
        case .outbound:
            return .initiator
        }
    }

    public var direction: ConnectionStats.Direction {
        self.stats.direction
    }

    public var expectedRemotePeer: PeerID? {
        try? self.remoteAddr?.getPeerID()
    }
}

public protocol ConnectionLifecycleDelegate: AnyObject {
    func onOpened() -> EventLoopFuture<Void>
    func onSecured(sec: SecurityProtocolInstaller, remotePeerID: PeerID?) -> EventLoopFuture<Void>
    func onMuxed(muxer: MuxerProtocolInstaller) -> EventLoopFuture<Void>
    func onUpgraded() -> EventLoopFuture<Void>
    func onClosing() -> EventLoopFuture<Void>
    func onClosed() -> EventLoopFuture<Void>
}

public protocol ConnectionDelegate {
    /// Generic callback for any new Stream
    var onNewStream: ((Stream) -> EventLoopFuture<Void>)? { get set }

    /// Events for a particular Stream (init, ready, closed outbound, closed inbound, closed, reset, etc...)
    var onStreamEvent: ((Stream, StreamEvent) -> EventLoopFuture<Void>)? { get set }

    /// Connection Events (opene
    var onConnectionEvent: ((Connection, ConnectionEvent) -> EventLoopFuture<Void>)? { get set }
}

/// Connection Metadata
public class ConnectionStats: CustomStringConvertible {
    typealias Time = Date
    public enum Status {
        case opening
        case open
        case upgraded
        case closing
        case closed
    }
    public enum Direction {
        case inbound
        case outbound
    }
    public class Timeline {
        let opening: Time
        var opened: Time?
        var upgraded: Time?
        var closing: Time?
        var closed: Time?

        /// Initializes a new Timeline by setting the `opening ` variable to the current date.
        init() { self.opening = Time() }

        public var description: String {
            var entries: [String] = ["Connection Timeline:"]
            entries.append("- Opening: \(opening)")
            if let opened = opened { entries.append("- Opened: \(opened)") }
            if let upgraded = upgraded { entries.append("- Upgraded: \(upgraded)") }
            if let closing = closing { entries.append("- Closing: \(closing)") }
            if let closed = closed { entries.append("- Closed: \(closed)") }
            return entries.joined(separator: "\n\t")
        }

        public var history: [Status: Date] {
            var hist: [Status: Time] = [.opening: opening]
            if let opened = opened { hist[.open] = opened }
            if let upgraded = upgraded { hist[.upgraded] = upgraded }
            if let closing = closing { hist[.closing] = closing }
            if let closed = closed { hist[.closed] = closed }
            return hist
        }
    }

    /// The status of the connection.
    /// - Note: It can be either open, closing or closed. Once the connection is created it is in an open status. When a conn.close() happens, the status will change to closing and finally, after all the connection streams are properly closed, the status will be closed
    /// - TODO: Should be a state machine that enforces one way state transistions and updates the timeline on didSet...
    public var status: Status {
        didSet {
            switch status {
            case .open:
                self.timeline.opened = Time()
            case .upgraded:
                self.timeline.upgraded = Time()
            case .closing:
                self.timeline.closing = Time()
            case .closed:
                self.timeline.closed = Time()
            default:
                return
            }
        }
    }

    /// The UUID of the Connection
    public let uuid: UUID

    /// The open, upgraded and close timestamps of the connection.
    /// - Note: that, the close timestamp is undefined until the connection is closed
    /// - TODO: Should be a get only variable (updated internally via status's didSet KVO method)
    public let timeline: Timeline

    /// The direction of the peer in the connection. It can be inbound or outbound
    public let direction: Direction

    /// The encryption method being used in the connection. It is undefined if the connection is not encrypted.
    public var encryption: String?

    /// The multiplexing codec being used in the connection (optional)
    public var muxer: String?

    public init(uuid: UUID, direction: Direction, muxer: String? = nil, encryption: String? = nil) {
        self.uuid = uuid
        self.direction = direction
        self.muxer = muxer
        self.encryption = encryption
        self.status = .opening
        self.timeline = Timeline()
    }

    public var description: String {
        """
        \n\tConnection ID: \(uuid)
        \tDirection: \(direction)
        \tSecurity: \(encryption?.description ?? "No Security")
        \tMuxed: \(muxer?.description ?? "Not Muxed")
        \tStatus: \(status)
        \t\(timeline.description)
        """
    }
}

public enum ConnectionState {
    case raw
    case secured
    case muxed
    case upgraded
    case closed
}

public enum ConnectionEvent {
    case initialized
    case dialing
    //case state(Transport)
    case ready
    case closing
    case closed
    case reset
    case error(Error)
}
