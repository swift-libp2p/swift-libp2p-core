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

public protocol Stream: AnyObject {
    /// The underlying connection this stream belongs to
    /// - Important: This must be a weakly held reference to our parent Connection
    var connection:Connection? { get }
    
    var channel:Channel { get }
    
    /// The non-unique ID of this stream
    var id:UInt64 { get }
    /// The name of this stream
    var name:String? { get }
    /// The state of this stream (usually either active or closed)
    var streamState:LibP2PCore.StreamState { get }
    /// The protocol codec this stream is registered to (every stream must be bound to a single protocol codec, ex: 'echo/1.0.0')
    var protocolCodec:String { get }
    /// The direction of the stream. Is it inbound (the remote initiated the stream, or outbound, we initiated it)
    var direction:ConnectionStats.Direction { get }
    
    /// Should change the Channel init requirement to Connection and update Connection to expose the channel for internal use?
    /// This might solve our Lazy instantiation issue we're dealing with... Cause right now in order to instantiate a Stream, we need a Channel and in order to have a channel, we need a Connection that has already reached out to the peer...
    init(channel:Channel, mode:LibP2PCore.Mode, id:UInt64, name:String?, proto:String, streamState:LibP2PCore.StreamState)
    
    /// Writes data to the remote peer
    //func write(_ data:Data) -> EventLoopFuture<Void>
    /// Writes bytes to the remote peer
    func write(_ bytes:[UInt8]) -> EventLoopFuture<Void>
    /// Writes bytes to the remote peer
    func write(_ buffer:ByteBuffer) -> EventLoopFuture<Void>
    
    /// A method that gets called when Stream Events are triggered
    var on:((LibP2PCore.StreamEvent) -> EventLoopFuture<Void>)? { get set }
    //func on(_ event:LibP2P.StreamEvent) -> EventLoopFuture<Void>
    
    /// Requests the Stream be closed on our end
    func close(gracefully:Bool) -> EventLoopFuture<Void>
    
    /// Requests that the Stream be reset immediately
    func reset() -> EventLoopFuture<Void>
        
    /// Called to actually dial the peer once configured
    func resume() -> EventLoopFuture<Void>
}

extension Stream {
    func close() -> EventLoopFuture<Void> {
        return self.close(gracefully: true)
    }
    
//    func hash(into hasher: inout Hasher) {
//        hasher.combine(channel.localAddress)
//        hasher.combine(channel.remoteAddress)
//        hasher.combine(id)
//        hasher.combine(name)
//        hasher.combine(protocolCodec)
//    }
}

public protocol _Stream: Stream {
    
    /// The underlying connection this stream belongs to
    /// - Important: This must be a weakly held reference to our parent Connection
    /// Holding a reference to the parent Connection object, gives us a bridge to accessing the channel in order to kick off writes and access the channels allocater, etc...
    var _connection:Connection? { get set }
    var _streamState:LibP2PCore.StreamState { get set }
    var mode:LibP2PCore.Mode { get }
    //var _channel:Channel? { get }
}

public final class StreamHandler {
    /// The actual, underlying, stream that this handler interacts with
    /// - Note: this will be nil before the stream is initialized by our Muxer and will be nil after the stream has been deinitialzed
    internal weak var _stream:Stream?
    
    /// The underlying connection this stream belongs to
    /// - Important: This must be a weakly held reference to our parent Connection
    internal weak var _connection:Connection?
    
    /// The underlying connection this stream belongs to
    /// - Important: This must be a weakly held reference to our parent Connection
    var connection:Connection? {
        _connection
    }
    
    var channel:Channel? {
        _connection?.channel
    }
    
    /// The non-unique ID of this stream
    var id:UInt64? {
        _stream?.id
    }
    /// The name of this stream
    var name:String? {
        _stream?.name
    }
    /// The state of this stream (usually either active or closed)
    var streamState:LibP2PCore.StreamState {
        _stream?.streamState ?? .initialized
    }
    /// The protocol codec this stream is registered to (every stream must be bound to a single protocol codec, ex: 'echo/1.0.0')
    let protocolCodec:String
    
    /// A method that gets called when Stream Events are triggered
    var on:((LibP2PCore.StreamEvent) -> EventLoopFuture<Void>)?
    
    init(protocolCodec:String) {
        self.protocolCodec = protocolCodec
    }
    
//    init(protocolName:String, version:String, handler:@escaping((LibP2P.StreamEvent) -> EventLoopFuture<Void>)) {
//        self.protocolCodec = protocolName + "/" + version
//        self.on = handler
//    }
//
//    init(protocolCodec:String, handler:@escaping((LibP2P.StreamEvent) -> EventLoopFuture<Void>)) {
//        self.protocolCodec = protocolCodec
//        self.on = handler
//    }
    
    /// Writes data to the remote peer
//    func write(_ data:Data, promise:EventLoopPromise<Void>? = nil) {
//        guard let s = _stream else {
//            promise?.fail(Errors.streamNotAvailable)
//            return
//        }
//        guard let promise = promise else {
//            let _ = s.write(data)
//            return
//        }
//        promise.completeWith(s.write(data))
//    }
    
    /// Writes bytes to the remote peer
    func write(_ bytes:[UInt8], promise:EventLoopPromise<Void>? = nil) {
        guard let s = _stream else {
            promise?.fail(Errors.streamNotAvailable)
            return
        }
        guard let promise = promise else {
            let _ = s.write(bytes)
            return
        }
        promise.completeWith(s.write(bytes))
    }
    
    /// Writes bytes to the remote peer
    func write(_ buffer:ByteBuffer, promise:EventLoopPromise<Void>? = nil) {
        guard let s = _stream else {
            promise?.fail(Errors.streamNotAvailable)
            return
        }
        guard let promise = promise else {
            let _ = s.write(buffer)
            return
        }
        promise.completeWith(s.write(buffer))
    }
    
    /// Requests the Stream be closed on our end
    func close(gracefully:Bool = true, promise:EventLoopPromise<Void>? = nil ) {
        guard let s = _stream else {
            promise?.fail(Errors.streamNotAvailable)
            return
        }
        guard let promise = promise else {
            let _ = s.close(gracefully: gracefully)
            return
        }
        promise.completeWith(s.close(gracefully: gracefully))
    }
    
    /// Requests that the Stream be reset immediately
    func reset(promise:EventLoopPromise<Void>? = nil) {
        guard let s = _stream else {
            promise?.fail(Errors.streamNotAvailable)
            return
        }
        guard let promise = promise else {
            let _ = s.reset()
            return
        }
        promise.completeWith(s.reset())
    }
        
    /// Called to actually dial the peer once configured
    func resume(promise:EventLoopPromise<Void>? = nil) {
        guard let s = _stream else {
            promise?.fail(Errors.streamNotAvailable)
            return
        }
        guard let promise = promise else {
            let _ = s.resume()
            return
        }
        promise.completeWith(s.resume())
    }
    
    
    public enum Errors:Error {
        case streamNotAvailable
    }
}

public enum StreamState:UInt8 {
    case initialized = 0
    case open
    case receiveClosed
    case writeClosed
    case closed
    case reset
}

public enum StreamEvent {
    case initialized
    case ready
    case closing
    case closed
    case reset
    case data(ByteBuffer)
    case error(Error)
    
    internal var rawValue:String {
        switch self {
        case .initialized: return "initialized"
        case .ready:       return "ready"
        case .closing:     return "closing"
        case .closed:      return "closed"
        case .reset:       return "reset"
        case .data:        return "data"
        case .error:       return "error"
        }
    }
}
