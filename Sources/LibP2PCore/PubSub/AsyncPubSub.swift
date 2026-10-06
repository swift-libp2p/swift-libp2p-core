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

public import NIOCore

/// A PubSub router with a native async API.
///
/// Adopt this alongside ``PubSubCore``, which stays the requirement for registering with `app.pubsub`
/// for now. Unlike ``PubSubCore/subscribe(_:)``, ``subscribe(_:)`` hands back its events as an
/// `AsyncSequence`, so nothing can be delivered before the caller is listening.
///
/// - Note: The method names deliberately differ from ``PubSubCore``'s async conveniences
///   (`unsubscribe(topic:)`, `publish(topic:data:)`, `getTopics()`) so a router can conform to both.
///   With both conformances, `try await router.subscribe(config)` resolves to this protocol's
///   ``subscribe(_:)``, which returns a ``PubSub/Subscription``.
public protocol AsyncPubSub: AnyObject, Sendable {
    /// The protocol ID this router speaks, e.g. `/meshsub/1.1.0`
    static var multicodec: String { get }

    /// Subscribes to `config.topic`, returning a ``PubSub/Subscription`` that delivers the topic's events.
    @discardableResult
    func subscribe(_ config: PubSub.SubscriptionConfig) async throws -> PubSub.Subscription

    /// Unsubscribes from `topic` entirely, finishing all of its subscriptions.
    func unsubscribe(from topic: String) async throws

    /// Publishes `data` to `topic`.
    func publish(_ data: Data, to topic: String) async throws

    /// The topics we're subscribed to.
    func subscribedTopics() async -> [String]

    /// The peers we know to be subscribed to `topic`.
    func peers(subscribedTo topic: String) async -> [PeerID]
}

extension AsyncPubSub {
    /// Publishes `bytes` to `topic`.
    public func publish(_ bytes: [UInt8], to topic: String) async throws {
        try await self.publish(Data(bytes), to: topic)
    }

    /// Publishes the readable bytes of `buffer` to `topic`.
    public func publish(_ buffer: ByteBuffer, to topic: String) async throws {
        try await self.publish(Data(buffer.readableBytesView), to: topic)
    }
}

extension PubSub {
    /// A subscription to a topic, delivering its events as an `AsyncSequence`.
    ///
    /// ```swift
    /// let subscription = try await router.subscribe(config)
    /// for await message in subscription.messages {
    ///     print(String(decoding: message.data, as: UTF8.self))
    /// }
    /// ```
    ///
    /// The subscription stays active until it's cancelled (``cancel()``, or cancelling the task that's
    /// iterating it) or until the router finishes it, e.g. on ``AsyncPubSub/unsubscribe(from:)``.
    ///
    /// - Important: Like any `AsyncStream`, a subscription supports a single consumer.
    public struct Subscription: AsyncSequence, Sendable {
        public typealias Element = SubscriptionEvent

        /// The topic this subscription is for
        public let topic: String

        private let events: AsyncStream<SubscriptionEvent>
        private let onCancel: @Sendable () -> Void

        /// Creates a subscription that delivers `events`, calling `onCancel` when ``cancel()`` is called.
        ///
        /// Routers that don't need custom cancellation can use ``makeStream(topic:bufferingPolicy:)``.
        public init(topic: String, events: AsyncStream<SubscriptionEvent>, onCancel: @escaping @Sendable () -> Void) {
            self.topic = topic
            self.events = events
            self.onCancel = onCancel
        }

        public func makeAsyncIterator() -> AsyncStream<SubscriptionEvent>.Iterator {
            self.events.makeAsyncIterator()
        }

        /// Just the messages published to the topic
        public var messages: AsyncCompactMapSequence<Subscription, PubSubMessage> {
            self.compactMap { event in
                guard case .data(let message) = event else { return nil }
                return message
            }
        }

        /// Ends the subscription.
        public func cancel() {
            self.onCancel()
        }

        /// Creates a subscription along with the continuation a router feeds its events into.
        ///
        /// ``cancel()`` finishes the continuation. Use `continuation.onTermination` to learn when the
        /// subscriber goes away, whether by cancelling, cancelling its task, or the router finishing it.
        ///
        /// - Parameter bufferingPolicy: How many undelivered events to hold onto. A slow subscriber
        ///   with a bounded policy loses events rather than growing without limit.
        public static func makeStream(
            topic: String,
            bufferingPolicy: AsyncStream<SubscriptionEvent>.Continuation.BufferingPolicy = .unbounded
        ) -> (subscription: Subscription, continuation: AsyncStream<SubscriptionEvent>.Continuation) {
            let (events, continuation) = AsyncStream.makeStream(of: SubscriptionEvent.self, bufferingPolicy: bufferingPolicy)
            let subscription = Subscription(topic: topic, events: events, onCancel: { continuation.finish() })
            return (subscription, continuation)
        }
    }
}
