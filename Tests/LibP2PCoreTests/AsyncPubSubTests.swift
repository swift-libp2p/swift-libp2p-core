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

import Foundation
import NIOConcurrencyHelpers
import NIOCore
import NIOEmbedded
import Testing

@testable import LibP2PCore

@Suite("AsyncPubSub Tests")
struct AsyncPubSubTests {

    struct Message: PubSubMessage {
        var from = Data()
        var data: Data
        var seqno = Data()
        var topicIds: [String]
        var signature = Data()
        var key = Data()
    }

    /// A loopback router that conforms to both `PubSubCore` and `AsyncPubSub`.
    /// Publishing delivers to our own subscriptions.
    final class LoopbackRouter: PubSubCore, AsyncPubSub, @unchecked Sendable {
        static let multicodec = "/loopback/1.0.0"

        let eventLoop: EventLoop = EmbeddedEventLoop()
        let state: ServiceLifecycleState = .started
        private let subscriptions = NIOLockedValueBox<[String: [AsyncStream<PubSub.SubscriptionEvent>.Continuation]]>([:])

        func start() throws {}
        func stop() throws {}

        // MARK: AsyncPubSub

        @discardableResult
        func subscribe(_ config: PubSub.SubscriptionConfig) async throws -> PubSub.Subscription {
            let (subscription, continuation) = PubSub.Subscription.makeStream(topic: config.topic)
            subscriptions.withLockedValue { $0[config.topic, default: []].append(continuation) }
            return subscription
        }

        func unsubscribe(from topic: String) async {
            let continuations = subscriptions.withLockedValue { $0.removeValue(forKey: topic) } ?? []
            for continuation in continuations { continuation.finish() }
        }

        func publish(_ data: Data, to topic: String) async throws {
            let message = Message(data: data, topicIds: [topic])
            let continuations = subscriptions.withLockedValue { $0[topic] } ?? []
            for continuation in continuations { continuation.yield(.data(message)) }
        }

        func subscribedTopics() async -> [String] {
            subscriptions.withLockedValue { $0.keys.sorted() }
        }

        func peers(subscribedTo topic: String) async -> [PeerID] { [] }

        // MARK: PubSubCore (unused by these tests)

        func subscribe(_ config: PubSub.SubscriptionConfig, on loop: EventLoop?) -> EventLoopFuture<Void> {
            eventLoop.makeSucceededVoidFuture()
        }
        func subscribe(_ config: PubSub.SubscriptionConfig) throws -> PubSub.SubscriptionHandler {
            PubSub.SubscriptionHandler(pubSub: self, topic: config.topic)
        }
        func unsubscribe(topic: String, on: EventLoop?) -> EventLoopFuture<Void> { eventLoop.makeSucceededVoidFuture() }
        func getTopics(on: EventLoop?) -> EventLoopFuture<[String]> { eventLoop.makeSucceededFuture([]) }
        func getPeersSubscribed(to topic: String, on: EventLoop?) -> EventLoopFuture<[PeerID]> {
            eventLoop.makeSucceededFuture([])
        }
        func publish(topic: String, data: Data, on: EventLoop?) -> EventLoopFuture<Void> {
            eventLoop.makeSucceededVoidFuture()
        }
        func publish(topic: String, bytes: [UInt8], on: EventLoop?) -> EventLoopFuture<Void> {
            eventLoop.makeSucceededVoidFuture()
        }
        func publish(topic: String, buffer: ByteBuffer, on: EventLoop?) -> EventLoopFuture<Void> {
            eventLoop.makeSucceededVoidFuture()
        }
    }

    static func config(_ topic: String) -> PubSub.SubscriptionConfig {
        PubSub.SubscriptionConfig(topic: topic, validator: .acceptAll, messageIDFunc: .concatFromAndSequenceFields)
    }

    // MARK: - PubSub.Subscription

    @Test func subscriptionDeliversEventsInOrder() async {
        let (subscription, continuation) = PubSub.Subscription.makeStream(topic: "news")
        continuation.yield(.data(Message(data: Data("one".utf8), topicIds: ["news"])))
        continuation.yield(.error(CancellationError()))
        continuation.yield(.data(Message(data: Data("two".utf8), topicIds: ["news"])))
        continuation.finish()

        var kinds: [String] = []
        for await event in subscription { kinds.append(event.rawValue) }
        #expect(kinds == ["data", "error", "data"])
        #expect(subscription.topic == "news")
    }

    @Test func messagesOnlyYieldsData() async {
        let (subscription, continuation) = PubSub.Subscription.makeStream(topic: "news")
        continuation.yield(.error(CancellationError()))
        continuation.yield(.data(Message(data: Data("one".utf8), topicIds: ["news"])))
        continuation.yield(.data(Message(data: Data("two".utf8), topicIds: ["news"])))
        continuation.finish()

        var payloads: [String] = []
        for await message in subscription.messages { payloads.append(String(decoding: message.data, as: UTF8.self)) }
        #expect(payloads == ["one", "two"])
    }

    @Test func cancelFinishesTheSubscription() async {
        let (subscription, continuation) = PubSub.Subscription.makeStream(topic: "news")
        let terminated = NIOLockedValueBox(false)
        continuation.onTermination = { _ in terminated.withLockedValue { $0 = true } }

        subscription.cancel()

        #expect(terminated.withLockedValue { $0 })
        if case .terminated = continuation.yield(.error(CancellationError())) {} else {
            Issue.record("expected yields after cancel() to be dropped")
        }
        var count = 0
        for await _ in subscription { count += 1 }
        #expect(count == 0)
    }

    @Test func customOnCancelIsCalled() {
        let (events, _) = AsyncStream.makeStream(of: PubSub.SubscriptionEvent.self)
        let cancelled = NIOLockedValueBox(0)
        let subscription = PubSub.Subscription(topic: "news", events: events) {
            cancelled.withLockedValue { $0 += 1 }
        }
        subscription.cancel()
        #expect(cancelled.withLockedValue { $0 } == 1)
    }

    @Test func boundedBufferingPolicyDropsOldestEvents() async {
        let (subscription, continuation) = PubSub.Subscription.makeStream(topic: "news", bufferingPolicy: .bufferingNewest(2))
        for payload in ["one", "two", "three"] {
            continuation.yield(.data(Message(data: Data(payload.utf8), topicIds: ["news"])))
        }
        continuation.finish()

        var payloads: [String] = []
        for await message in subscription.messages { payloads.append(String(decoding: message.data, as: UTF8.self)) }
        #expect(payloads == ["two", "three"])
    }

    // MARK: - AsyncPubSub

    /// With both conformances, `subscribe(_:)` must resolve to `AsyncPubSub`'s, through the concrete
    /// type and through an existential, rather than `PubSubCore`'s `Void` async convenience.
    @Test func subscribeResolvesToTheAsyncPubSubOverload() async throws {
        let router = LoopbackRouter()
        let concrete = try await router.subscribe(Self.config("a"))
        let _: PubSub.Subscription = concrete

        let both: any PubSubCore & AsyncPubSub = router
        let existential = try await both.subscribe(Self.config("b"))
        let _: PubSub.Subscription = existential

        let asyncOnly: any AsyncPubSub = router
        try await asyncOnly.subscribe(Self.config("c"))

        #expect(await router.subscribedTopics() == ["a", "b", "c"])
    }

    @Test func publishDeliversToSubscribers() async throws {
        let router = LoopbackRouter()
        let subscription = try await router.subscribe(Self.config("news"))

        try await router.publish(Data("data".utf8), to: "news")
        try await router.publish(Array("bytes".utf8), to: "news")
        try await router.publish(ByteBuffer(string: "buffer"), to: "news")
        await router.unsubscribe(from: "news")

        var payloads: [String] = []
        for await message in subscription.messages { payloads.append(String(decoding: message.data, as: UTF8.self)) }
        #expect(payloads == ["data", "bytes", "buffer"])
    }

    @Test func unsubscribeFinishesSubscriptions() async throws {
        let router = LoopbackRouter()
        let first = try await router.subscribe(Self.config("news"))
        let second = try await router.subscribe(Self.config("news"))

        try await (router as any AsyncPubSub).unsubscribe(from: "news")

        for subscription in [first, second] {
            var count = 0
            for await _ in subscription { count += 1 }
            #expect(count == 0)
        }
        #expect(await router.subscribedTopics().isEmpty)
    }

    @Test func multicodecIsReachableThroughTheProtocol() {
        func codec<R: AsyncPubSub>(_: R.Type) -> String { R.multicodec }
        #expect(codec(LoopbackRouter.self) == "/loopback/1.0.0")
    }
}
