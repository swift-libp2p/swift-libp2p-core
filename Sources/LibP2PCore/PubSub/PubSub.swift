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

public enum PubSub {
    /// ValidationResult represents the decision of an extended validator
    public enum ValidationResult {
        /// Accept is a validation decision that indicates a valid message that should be accepted and delivered to the application and forwarded to the network.
        case accept
        /// Reject is a validation decision that indicates an invalid message that should not be delivered to the application or forwarded to the application. Furthermore the peer that forwarded the message should be penalized by peer scoring routers.
        case reject
        /// Ignore is a validation decision that indicates a message that should be ignored: it will be neither delivered to the application nor forwarded to the network. However, in contrast to `Reject`, the peer that forwarded the message must not be penalized by peer scoring routers.
        case ignore
        /// Used Internally to throttle messages from a particular peer
        case throttle
    }

    public enum SubscriptionEvent {
        case newPeer(PeerID)
        case data(PubSubMessage)
        case error(Error)

        public var rawValue:String {
            switch self {
            case .newPeer:     return "newPeer"
            case .data:        return "data"
            case .error:       return "error"
            }
        }
    }
    
    public struct SubscriptionConfig {
        public let topic:String
        public let signaturePolicy:SignaturePolicy
        public let validator:ValidatorFunction
        public let messageIDFunc:MessageIDFunction
        
        public init(topic:String, signaturePolicy:SignaturePolicy = .strictSign, validator:ValidatorFunction, messageIDFunc:MessageIDFunction) {
            self.topic = topic
            self.signaturePolicy = signaturePolicy
            self.validator = validator
            self.messageIDFunc = messageIDFunc
        }
    }
    
    public enum SignaturePolicy {
        case strictSign
        case strictNoSign
    }
    
    public enum ValidatorFunction {
        /// Doesn't perform any Message Validation, accepts all inbound messages
        case acceptAll
        /// Perform custom Message Validation on each inbound message (like passing the message through a blacklist and rejecting message from certain senders)
        case custom((_:PubSubMessage) -> Bool)
        
        public var validationFunction:((_:PubSubMessage) -> Bool) {
            switch self {
            case .acceptAll:
                return { _ in true }
            case .custom(let f):
                return f
            }
        }
    }
    
    public final class SubscriptionHandler {
        /// The topic this subscription is tied to
        private weak var pubsub:PubSubCore?
        let topic:String
        
        /// A method that gets called when Stream Events are triggered
        public var on:((SubscriptionEvent) -> EventLoopFuture<Void>)?
        
        public init(pubSub:PubSubCore, topic:String) {
            self.pubsub = pubSub
            self.topic = topic
        }
        
        /// Writes data to the remote peer
        public func publish(_ data:Data, promise:EventLoopPromise<Void>? = nil) {
            guard let ps = pubsub else {
                promise?.fail(Errors.subscriptionNotAvailable)
                return
            }
            guard let promise = promise else {
                let _ = ps.publish(topic: self.topic, data: data, on: nil)
                return
            }
            promise.completeWith(ps.publish(topic: self.topic, data: data, on: nil))
        }
        
        /// Writes bytes to the remote peer
        public func publish(_ bytes:[UInt8], promise:EventLoopPromise<Void>? = nil) {
            guard let ps = pubsub else {
                promise?.fail(Errors.subscriptionNotAvailable)
                return
            }
            guard let promise = promise else {
                let _ = ps.publish(topic: self.topic, bytes: bytes, on: nil)
                return
            }
            promise.completeWith(ps.publish(topic: self.topic, bytes: bytes, on: nil))
        }
        
        /// Writes bytes to the remote peer
        public func publish(_ buffer:ByteBuffer, promise:EventLoopPromise<Void>? = nil) {
            guard let ps = pubsub else {
                promise?.fail(Errors.subscriptionNotAvailable)
                return
            }
            guard let promise = promise else {
                let _ = ps.publish(topic: self.topic, buffer: buffer, on: nil)
                return
            }
            promise.completeWith(ps.publish(topic: self.topic, buffer: buffer, on: nil))
        }
        
        public func unsubscribe(promise:EventLoopPromise<Void>? = nil) {
            guard let ps = pubsub else {
                promise?.fail(Errors.subscriptionNotAvailable)
                return
            }
            let _ = ps.unsubscribe(topic: self.topic, on: nil)
        }
        
        func makeSucceededVoidFuture() -> EventLoopFuture<Void> {
            (self.pubsub?.eventLoop.makeSucceededVoidFuture())!
        }
        
        public enum Errors:Error {
            case subscriptionNotAvailable
        }
    }
    
    public enum MessageIDFunction {
        /// Calculates a Message's ID by hashing the Message Sequence Number and the Message Sender
        case hashSequenceNumberAndFromFields
        /// Calculates a Message's ID by hashing the Sequence Number, Sender, Data and Topic fields
        case hashEverything
        /// Simply concatenates the messages From data and Sequence Number (default message id function)
        case concatFromAndSequenceFields
        /// Specify your own custom method for generating a Message's ID
        case custom((_:PubSubMessage) -> Data)
        
        public var messageIDFunction:((_:PubSubMessage) -> Data) {
            switch self {
            case .hashSequenceNumberAndFromFields:
                return { message in
                    var hasher = Hasher()
                    hasher.combine(message.seqno)
                    hasher.combine(message.from)
                    return withUnsafeBytes(of: hasher.finalize().littleEndian) { Data($0) }
                }
            case .hashEverything:
                return { message in
                    var hasher = Hasher()
                    hasher.combine(message.seqno)
                    hasher.combine(message.from)
                    hasher.combine(message.data)
                    hasher.combine(message.topicIds)
                    return withUnsafeBytes(of: hasher.finalize().littleEndian) { Data($0) }
                }
            case .concatFromAndSequenceFields:
                return { message in
                    return message.from + message.seqno
                }
            case .custom(let f):
                return f
            }
        }
    }
    
    public enum MessageState {
        public enum FilterType {
            case known
            case unknown
            case full
        }
    }
    
    public struct Subscriber {
        public let id:PeerID
        public private(set) var inbound:Stream?
        public private(set) var outbound:Stream?
        
        public init(id:PeerID, inbound:Stream? = nil, outbound:Stream? = nil) {
            self.id = id
            self.inbound = inbound
            self.outbound = outbound
        }
        
        public func write(_ bytes:[UInt8]) throws {
            guard let outbound = outbound else {
                throw Errors.noOutboundStream
            }
            let _ = outbound.write(bytes)
        }
        
        public func close(on:EventLoop) -> EventLoopFuture<Void> {
            EventLoopFuture.whenAllComplete([
                (self.inbound?.close(gracefully: true) ?? on.makeSucceededVoidFuture()),
                (self.outbound?.close(gracefully: true) ?? on.makeSucceededVoidFuture())
            ], on: on).map { _ in print("Closed Subscriber<\(id)> Streams") }
        }
        
        public mutating func attachInbound(stream:Stream) {
            guard stream.direction == .inbound, stream.connection?.remotePeer == id else { return }
            self.inbound = stream
        }
        
        public mutating func attachOutbound(stream:Stream) {
            guard stream.direction == .outbound, stream.connection?.remotePeer == id else { return }
            self.outbound = stream
        }
        
        public mutating func detachInboundStream() {
            self.inbound = nil
        }
        
        public mutating func detachOutboundStream() {
            self.outbound = nil
        }
        
        public enum Errors:Error {
            case noOutboundStream
        }
    }
}

//public protocol PubSubMessageIDFunction {
//    /// Given a message, this function should return a unique id used to determine duplicate / redundant messages
//    func messageID(_ msg:PubSubMessage) -> [UInt8]
//}

public protocol RPCMessageCore {
    var subs:[SubOptsCore] { get }
    var messages:[PubSubMessage] { get }
    //var control:ControlMessageCore { get }
}

public protocol ControlMessageCore { }

public protocol SubOptsCore {
    var subscribe:Bool { get }
    var topicID:String { get }
}

public protocol PubSubMessage:CustomStringConvertible {
    var from:Data { get }
    var data:Data { get }
    var seqno:Data { get }
    var topicIds:[String] { get }
    var signature:Data { get }
    var key:Data { get }
}

extension PubSubMessage {
    public var description: String {
        return """
        -- ✉️ ---------------------- ✉️ --
        RPC PubSub Message [\(self.topicIds.joined(separator: ", "))]:
        From: \(self.from.asString(base: .base58btc))
        SeqNo: \(self.seqno.asString(base: .base16))
        Data: \(String(data: self.data, encoding: .utf8) ?? "Not UTF8 Data")
        Signature: \(self.signature.asString(base: .base16))
        Key: \(self.key.asString(base: .base16))
        ----------------------------------
        """
    }
}

public protocol PubSubCore:EventLoopService, AnyObject {
    static var multicodec:String { get }
    
    func start() throws
    func stop() throws
    
    //func subscribe(topic:String, on:EventLoop?) -> EventLoopFuture<Void>
    func subscribe(_ config:PubSub.SubscriptionConfig, on loop:EventLoop?) -> EventLoopFuture<Void>
    func subscribe(_ config:PubSub.SubscriptionConfig) throws -> PubSub.SubscriptionHandler
    func unsubscribe(topic:String, on:EventLoop?) -> EventLoopFuture<Void>
    
    func getTopics(on:EventLoop?) -> EventLoopFuture<[String]>
    func getPeersSubscribed(to topic:String, on:EventLoop?) -> EventLoopFuture<[PeerID]>

    func publish(topic:String, data:Data, on:EventLoop?) -> EventLoopFuture<Void>
    func publish(topic:String, bytes:[UInt8], on:EventLoop?) -> EventLoopFuture<Void>
    func publish(topic:String, buffer:ByteBuffer, on:EventLoop?) -> EventLoopFuture<Void>
    
    
    //func publish(topics:[String], messages:[[UInt8]], on:EventLoop?) -> EventLoopFuture<Void>
    
    //func validate(message:RPCMessageCore, on:EventLoop?) -> EventLoopFuture<Bool>
    //func validateExtended(message:RPCMessageCore, on:EventLoop?) -> EventLoopFuture<PubSub.ValidationResult>
    //func processRPCMessage(_ message:RPCMessageCore) -> EventLoopFuture<Void>
    
    //func subscribe(config:SubscriptionConfig, on:EventLoop?) -> EventLoopFuture<Void>
    //func subscribe(topic:String) -> SubscriptionHandler
    //func subscribe(_ config:PubSub.SubscriptionConfig) throws -> PubSub.SubscriptionHandler
}

//protocol PubSubRouter {
//
//}
//
//extension PubSubCore {
//    func validateExtended(message:RPCMessageCore.MessageCore) -> PubSub.ValidationResult {
//        print("WARNING:ValidateExtended not implemented")
//        return .reject
//    }
//}

public protocol PeerConnectionDelegate {
    func onPeerConnected(peerID:PeerID, stream:Stream) -> EventLoopFuture<Void>
    func onPeerDisconnected(_:PeerID) -> EventLoopFuture<Void>
}


/// Use these protocols to abstract away the specifics for both PeerState and MessageCache
/// Like FloodSub might have a basic implementation while GossipSub has a more complex one. Either way, PubSubBase shouldn't care.
//public protocol PeerStateProtocol:EventLoopService, PeerConnectionDelegate {
//    func addNewPeer(_ peer:PeerInfo) -> EventLoopFuture<Bool>
//    func removePeer(_ peer:PeerID) -> EventLoopFuture<Void>
//    func update(topics:[String], for peer:PeerID) -> EventLoopFuture<Void>
//    func update(subscriptions:[String:Bool], for peer:PeerID) -> EventLoopFuture<Void>
//    func peersSubscribedTo(topic:String, on loop:EventLoop?) -> EventLoopFuture<[PeerID]>
//    func peersSubscribedTo2(topic:String, on loop:EventLoop?) -> EventLoopFuture<[(PeerID, Stream)]>
//    func topicSubscriptions(on loop:EventLoop?) -> EventLoopFuture<[String]>
//    func streamFor(_ peer:PeerID) -> EventLoopFuture<Stream>
//    func isFullPeer(_ peer:PeerID) -> EventLoopFuture<Bool>
//    func makeFullPeer(_ peer:PeerID, for topic:String) -> EventLoopFuture<Void>
//    func makeMetaPeer(_ peer:PeerID, for topic:String) -> EventLoopFuture<Void>
//    func subscribeSelf(to topic:String, on loop:EventLoop?) -> EventLoopFuture<[String]>
//    func unsubscribeSelf(from topic:String, on loop:EventLoop?) -> EventLoopFuture<[String]>
//    //func peerExists(_ peer:PeerID, atAddress address:Multiaddr, on loop:EventLoop?) -> EventLoopFuture<Bool>
//}

public protocol PeerStateProtocol:EventLoopService, PeerConnectionDelegate {
    // Add and Remove Peers
    func addNewPeer(_ peer:PeerID, on:EventLoop?) -> EventLoopFuture<Bool>
    func removePeer(_ peer:PeerID, on:EventLoop?) -> EventLoopFuture<Void>
    
    // Attach inbound & outbound streams to existing peer
    func attachInboundStream(_ peer:PeerID, inboundStream:Stream, on:EventLoop?) -> EventLoopFuture<Void>
    func attachOutboundStream(_ peer:PeerID, outboundStream:Stream, on:EventLoop?) -> EventLoopFuture<Void>
    func detachInboundStream(_ peer:PeerID, on:EventLoop?) -> EventLoopFuture<Void>
    func detachOutboundStream(_ peer:PeerID, on:EventLoop?) -> EventLoopFuture<Void>
    
    // Update topics / subscriptions
    func update(topics:[String], for peer:PeerID, on:EventLoop?) -> EventLoopFuture<Void>
    func update(subscriptions:[String:Bool], for peer:PeerID, on:EventLoop?) -> EventLoopFuture<Void>
    func peersSubscribedTo(topic:String, on loop:EventLoop?) -> EventLoopFuture<[PubSub.Subscriber]>
    func getAllPeers(on loop:EventLoop?) -> EventLoopFuture<[PubSub.Subscriber]>
    func topicSubscriptions(on loop:EventLoop?) -> EventLoopFuture<[String]>
    func subscribeSelf(to topic:String, on loop:EventLoop?) -> EventLoopFuture<[String]>
    func unsubscribeSelf(from topic:String, on loop:EventLoop?) -> EventLoopFuture<[String]>
    
    // Get a peers inbound / outbound streams
    func streamsFor(_ peer:PeerID, on:EventLoop?) -> EventLoopFuture<PubSub.Subscriber>
    
    //func peerExists(_ peer:PeerID, atAddress address:Multiaddr, on loop:EventLoop?) -> EventLoopFuture<Bool>
}

/// Use these protocols to abstract away the specifics for both PeerState and MessageCache
/// Like FloodSub might have a basic implementation while GossipSub has a more complex one. Either way, PubSubBase shouldn't care.
public protocol MessageStateProtocol:EventLoopService {
    func put(messageID:Data, message:(topic:String, data:PubSubMessage), on loop:EventLoop?) -> EventLoopFuture<Bool>
    func put(messages:[Data:PubSubMessage], on loop:EventLoop?) -> EventLoopFuture<[Data:PubSubMessage]>
    func get(messageID:Data, on loop:EventLoop?) -> EventLoopFuture<(topic:String, data:PubSubMessage)?>
    func exists(messageID:Data, on loop:EventLoop?) -> EventLoopFuture<Bool>
    func filter(ids:Set<Data>, returningOnly:PubSub.MessageState.FilterType, on loop:EventLoop?) -> EventLoopFuture<[Data]>
}
