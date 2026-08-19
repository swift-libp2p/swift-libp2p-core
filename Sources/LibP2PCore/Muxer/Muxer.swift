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

    /// Takes an uninitialized Stream from our Connection object and attempts to open the Stream with the Remote Peer.
    func openStream(_ stream: inout Stream) throws -> EventLoopFuture<Void>

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
    let onStream: ((Stream) -> Void)?

    /// A function called when a stream ends.
    let onStreamEnd: ((Stream) -> Void)?

    /// An `AbortSignal` which can be used to abort the muxer, including all of it's multiplexed connections.
    let signal: (() -> Void)?

    /// The maximum size in bytes the data field of multiplexed messages may contain (default 1MB)
    let maxMessageSize: Int
}

public protocol MuxerProtocolInstaller {
    var protocolName: String { get }
    var protocolVersion: String { get }

    var muxer: Muxer? { get }

    //    func installHandlers(on ctx:ChannelHandlerContext, at position:ChannelPipeline.Position, localPeer:PeerID, mode:LibP2P.Mode, supportedProtocols:[LibP2P.ProtocolRegistration], upgraded:@escaping((Result<Bool, Error>) -> Void)) -> EventLoopFuture<Void>

    func installHandlers(
        on ctx: ChannelHandlerContext,
        at position: ChannelPipeline.Position,
        localPeer: PeerID,
        mode: Mode,
        supportedProtocols: [ProtocolRegistration],
        upgraded: EventLoopPromise<Muxer>
    ) -> EventLoopFuture<Void>

    func protocolString() -> String

    func destroySelf()
}

extension MuxerProtocolInstaller {
    public func protocolString() -> String {
        if protocolVersion.isEmpty { return protocolName }
        return "/\(protocolName)/\(protocolVersion)"
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

extension MuxerProtocolInstaller {
    /// Installs the muxer handlers and awaits the upgraded `Muxer`.
    public func installHandlers(
        on ctx: ChannelHandlerContext,
        at position: ChannelPipeline.Position,
        localPeer: PeerID,
        mode: Mode,
        supportedProtocols: [ProtocolRegistration]
    ) async throws -> Muxer {
        let promise = ctx.eventLoop.makePromise(of: Muxer.self)
        let upgraded = promise.futureResult
        try await self.installHandlers(
            on: ctx,
            at: position,
            localPeer: localPeer,
            mode: mode,
            supportedProtocols: supportedProtocols,
            upgraded: promise
        ).get()
        return try await upgraded.get()
    }
}
