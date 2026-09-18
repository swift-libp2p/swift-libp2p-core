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
public import Logging
import Multiaddr
import NIOConcurrencyHelpers
import NIOCore
import PeerID

/// The connection interface contains all the metadata associated with it, as well as an array of the streams opened through this connection
///
/// - Libp2p Streams ≈ Swift NIO Channels
/// - Libp2p Connection ≈ Swift NIO Client (or maybe Libp2p Transport is more akin to the Client, and Channel is a parent wrapper that handles meta data surrounding the client, streams and peer)
///
/// [LibP2P Connection Interface Documentation](https://github.com/libp2p/js-libp2p-interfaces/tree/master/src/connection)
public protocol Connection: AnyObject, Sendable {

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
    func onSecured(sec: Security, remotePeerID: PeerID?) -> EventLoopFuture<Void>
    func onMuxed(muxer: Muxer) -> EventLoopFuture<Void>
    func onUpgraded() -> EventLoopFuture<Void>
    func onClosing() -> EventLoopFuture<Void>
    func onClosed() -> EventLoopFuture<Void>
}

public protocol ConnectionDelegate {
    /// Generic callback for any new Stream
    var onNewStream: (@Sendable (Stream) -> EventLoopFuture<Void>)? { get set }

    /// Events for a particular Stream (init, ready, closed outbound, closed inbound, closed, reset, etc...)
    var onStreamEvent: (@Sendable (Stream, StreamEvent) -> EventLoopFuture<Void>)? { get set }

    /// Connection Events (opene
    var onConnectionEvent: (@Sendable (Connection, ConnectionEvent) -> EventLoopFuture<Void>)? { get set }
}

/// Connection Metadata
///
/// - Note: `ConnectionStats` is a *checked* `Sendable` reference type: all of its mutable state
///   (status, encryption, muxer codec, and the timeline timestamps) lives behind a single
///   `NIOLockedValueBox`, so the public `var` accessors are individually thread-safe. (It is still
///   event-loop-confined in practice; the lock exists to satisfy `Sendable` without forcing every
///   caller onto one loop.)
public final class ConnectionStats: CustomStringConvertible, Sendable {
    public enum Status: Sendable {
        case opening
        case open
        case upgraded
        case closing
        case closed
    }
    public enum Direction: Sendable {
        case inbound
        case outbound
    }

    /// A point-in-time snapshot of a connection's lifecycle timestamps.
    ///
    /// - Note: This became a `Sendable` value type (was a class) as part of making `ConnectionStats`
    ///   checked-`Sendable`. `ConnectionStats.timeline` returns a snapshot; mutation happens through
    ///   `ConnectionStats.status`.
    public struct Timeline: Sendable {
        public internal(set) var opening: Date
        public internal(set) var opened: Date?
        public internal(set) var upgraded: Date?
        public internal(set) var closing: Date?
        public internal(set) var closed: Date?

        /// Initializes a new Timeline by setting the `opening` timestamp to the current date.
        init() { self.opening = Date() }

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
            var hist: [Status: Date] = [.opening: opening]
            if let opened = opened { hist[.open] = opened }
            if let upgraded = upgraded { hist[.upgraded] = upgraded }
            if let closing = closing { hist[.closing] = closing }
            if let closed = closed { hist[.closed] = closed }
            return hist
        }
    }

    /// The mutable state, guarded so `ConnectionStats` is checked-`Sendable`.
    private struct State {
        var status: Status
        var encryption: String?
        var muxer: String?
        var timeline: Timeline
    }
    private let state: NIOLockedValueBox<State>

    /// The status of the connection.
    /// - Note: Setting the status also stamps the corresponding `timeline` timestamp (opened /
    ///   upgraded / closing / closed).
    /// - Important: The setter exists for the `Connection` implementation that owns these stats.
    ///   Nothing else should mutate a live connection's state.
    public var status: Status {
        get { self.state.withLockedValue { $0.status } }
        set {
            self.state.withLockedValue {
                $0.status = newValue
                switch newValue {
                case .open: $0.timeline.opened = Date()
                case .upgraded: $0.timeline.upgraded = Date()
                case .closing: $0.timeline.closing = Date()
                case .closed: $0.timeline.closed = Date()
                case .opening: break
                }
            }
        }
    }

    /// The UUID of the Connection
    public let uuid: UUID

    /// A snapshot of the connection's open / upgraded / close timestamps.
    public var timeline: Timeline {
        self.state.withLockedValue { $0.timeline }
    }

    /// The direction of the peer in the connection. It can be inbound or outbound
    public let direction: Direction

    /// The encryption method being used in the connection. It is undefined if the connection is not encrypted.
    public var encryption: String? {
        get { self.state.withLockedValue { $0.encryption } }
        set { self.state.withLockedValue { $0.encryption = newValue } }
    }

    /// The multiplexing codec being used in the connection (optional)
    public var muxer: String? {
        get { self.state.withLockedValue { $0.muxer } }
        set { self.state.withLockedValue { $0.muxer = newValue } }
    }

    public init(uuid: UUID, direction: Direction, muxer: String? = nil, encryption: String? = nil) {
        self.uuid = uuid
        self.direction = direction
        self.state = .init(State(status: .opening, encryption: encryption, muxer: muxer, timeline: Timeline()))
    }

    public var description: String {
        let snapshot = self.state.withLockedValue { $0 }
        return """
            \n\tConnection ID: \(uuid)
            \tDirection: \(direction)
            \tSecurity: \(snapshot.encryption?.description ?? "No Security")
            \tMuxed: \(snapshot.muxer?.description ?? "Not Muxed")
            \tStatus: \(snapshot.status)
            \t\(snapshot.timeline.description)
            """
    }
}

public enum ConnectionState: Sendable {
    case raw
    case secured
    case muxed
    case upgraded
    case closed
}

public enum ConnectionEvent: Sendable {
    case initialized
    case dialing
    //case state(Transport)
    case ready
    case closing
    case closed
    case reset
    case error(Error)
}

// MARK: - Async

extension Connection {
    public func inboundMuxedChildChannelInitializer(_ childChannel: Channel) async throws {
        try await self.inboundMuxedChildChannelInitializer(childChannel).get()
    }

    public func outboundMuxedChildChannelInitializer(_ childChannel: Channel, protocol proto: String) async throws {
        try await self.outboundMuxedChildChannelInitializer(childChannel, protocol: proto).get()
    }

    public func newStream(_ protos: [String]) async throws -> Stream {
        try await self.newStream(protos).get()
    }

    public func removeStream(id: UInt64) async throws {
        try await self.removeStream(id: id).get()
    }

    public func acceptStream(_ stream: Stream, protocol proto: String, metadata: [String]) async throws -> Bool {
        try await self.acceptStream(stream, protocol: proto, metadata: metadata).get()
    }

    public func close() async throws {
        try await self.close().get()
    }
}

extension ConnectionLifecycleDelegate {
    public func onOpened() async throws {
        try await self.onOpened().get()
    }

    public func onSecured(sec: Security, remotePeerID: PeerID?) async throws {
        try await self.onSecured(sec: sec, remotePeerID: remotePeerID).get()
    }

    public func onMuxed(muxer: Muxer) async throws {
        try await self.onMuxed(muxer: muxer).get()
    }

    public func onUpgraded() async throws {
        try await self.onUpgraded().get()
    }

    public func onClosing() async throws {
        try await self.onClosing().get()
    }

    public func onClosed() async throws {
        try await self.onClosed().get()
    }
}
