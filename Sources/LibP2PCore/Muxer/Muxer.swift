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

import NIOCore

public protocol Muxer: AnyObject {
    static var protocolCodec: String { get }
    //init(_ config:MuxerConfig?)

    /// Use this property as an alternative to passing onStream as an option to the Muxer constructor.
    var onStream: ((_Stream) -> Void)? { get set }

    /// Use this property as an alternative to passing onStreamEnd as an option to the Muxer constructor.
    var onStreamEnd: ((Stream) -> Void)? { get set }

    /// We use this property to provide the muxer with a weakly held reference to the underlying Connection object
    var _connection: Connection? { get set }

    /// Initiate a new stream with the remote. Returns a duplex stream.
    func newStream(channel: Channel, proto: String) throws -> EventLoopFuture<_Stream>

    /// Initiate a new stream with the remote. Returns a duplex stream.
    func newStream(channel: Channel, proto: ProtocolRegistration) throws -> EventLoopFuture<_Stream>

    /// The streams property returns an array of streams the muxer currently has open. Closed streams will not be returned.
    var streams: [Stream] { get }

    func getStream(id: UInt64, mode: Mode) -> EventLoopFuture<Stream?>

    /// Our Muxer doesn't have a way of knowing when a childChannel has negotiated it's protocols and upgraded it's state. This method lets us tell the Muxer about that...
    func updateStream(channel: Channel, state: StreamState, proto: String) -> EventLoopFuture<Void>

    /// Used to force the removal of a certain stream from our muxer...
    func removeStream(channel: Channel)
}

extension Muxer {
    public func newStream(channel: Channel, proto: ProtocolRegistration) throws -> EventLoopFuture<_Stream> {
        try self.newStream(channel: channel, proto: proto.protocolString())
    }

    public var protocolCodec: String {
        Self.protocolCodec
    }
}

public struct MuxerConfig {
    ///  A function called when receiving a new stream from the remote
    public let onStream: ((Stream) -> Void)?

    /// A function called when a stream ends.
    public let onStreamEnd: ((Stream) -> Void)?

    /// An `AbortSignal` which can be used to abort the muxer, including all of it's multiplexed connections.
    public let signal: (() -> Void)?

    /// The maximum size in bytes the data field of multiplexed messages may contain (default 1MB)
    public let maxMessageSize: Int

    public init(
        onStream: ((Stream) -> Void)? = nil,
        onStreamEnd: ((Stream) -> Void)? = nil,
        signal: (() -> Void)? = nil,
        maxMessageSize: Int = 1_048_576
    ) {
        self.onStream = onStream
        self.onStreamEnd = onStreamEnd
        self.signal = signal
        self.maxMessageSize = maxMessageSize
    }
}

// MARK: - Async

extension Muxer {
    public func newStream(channel: Channel, proto: String) async throws -> _Stream {
        try await self.newStream(channel: channel, proto: proto).get()
    }

    public func newStream(channel: Channel, proto: ProtocolRegistration) async throws -> _Stream {
        try await self.newStream(channel: channel, proto: proto).get()
    }

    public func getStream(id: UInt64, mode: Mode) async throws -> Stream? {
        try await self.getStream(id: id, mode: mode).get()
    }

    public func updateStream(channel: Channel, state: StreamState, proto: String) async throws {
        try await self.updateStream(channel: channel, state: state, proto: proto).get()
    }
}
