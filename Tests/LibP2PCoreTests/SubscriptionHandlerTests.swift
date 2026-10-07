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
import LibP2PCrypto
import NIOConcurrencyHelpers
import NIOCore
import NIOEmbedded
import Testing

@testable import LibP2PCore

@Suite("SubscriptionHandler Tests")
struct SubscriptionHandlerTests {

    struct ServiceError: Error, Equatable {}

    /// A PubSubCore that records unsubscribes and answers them with a configurable result.
    final class MockPubSub: PubSubCore, @unchecked Sendable {
        static let multicodec = "/mock/pubsub/1.0.0"

        let eventLoop: EventLoop
        let state: ServiceLifecycleState = .started
        let unsubscribeResult: Result<Void, Error>
        private let unsubscribed = NIOLockedValueBox<[String]>([])

        var unsubscribedTopics: [String] { unsubscribed.withLockedValue { $0 } }

        init(eventLoop: EventLoop, unsubscribeResult: Result<Void, Error> = .success(())) {
            self.eventLoop = eventLoop
            self.unsubscribeResult = unsubscribeResult
        }

        func start() throws {}
        func stop() throws {}

        func subscribe(_ config: PubSub.SubscriptionConfig, on loop: EventLoop?) -> EventLoopFuture<Void> {
            eventLoop.makeSucceededVoidFuture()
        }

        func subscribe(_ config: PubSub.SubscriptionConfig) throws -> PubSub.SubscriptionHandler {
            PubSub.SubscriptionHandler(pubSub: self, topic: config.topic)
        }

        func unsubscribe(topic: String, on: EventLoop?) -> EventLoopFuture<Void> {
            unsubscribed.withLockedValue { $0.append(topic) }
            return eventLoop.makeCompletedFuture(unsubscribeResult)
        }

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

    @Test func unsubscribePromiseSucceedsWithTheService() throws {
        let loop = EmbeddedEventLoop()
        let pubsub = MockPubSub(eventLoop: loop)
        let handler = PubSub.SubscriptionHandler(pubSub: pubsub, topic: "news")

        let promise = loop.makePromise(of: Void.self)
        handler.unsubscribe(promise: promise)

        try promise.futureResult.wait()
        #expect(pubsub.unsubscribedTopics == ["news"])
    }

    @Test func unsubscribePromiseFailsWithTheServicesError() {
        let loop = EmbeddedEventLoop()
        let pubsub = MockPubSub(eventLoop: loop, unsubscribeResult: .failure(ServiceError()))
        let handler = PubSub.SubscriptionHandler(pubSub: pubsub, topic: "news")

        let promise = loop.makePromise(of: Void.self)
        handler.unsubscribe(promise: promise)

        #expect(throws: ServiceError()) { try promise.futureResult.wait() }
    }

    @Test func unsubscribeWithoutAPromiseStillUnsubscribes() {
        let pubsub = MockPubSub(eventLoop: EmbeddedEventLoop())
        let handler = PubSub.SubscriptionHandler(pubSub: pubsub, topic: "news")

        handler.unsubscribe()

        #expect(pubsub.unsubscribedTopics == ["news"])
    }

    @Test func unsubscribeFailsOnceThePubSubIsGone() {
        let loop = EmbeddedEventLoop()
        var pubsub: MockPubSub? = MockPubSub(eventLoop: loop)
        let handler = PubSub.SubscriptionHandler(pubSub: pubsub!, topic: "news")
        pubsub = nil

        let promise = loop.makePromise(of: Void.self)
        handler.unsubscribe(promise: promise)

        #expect(throws: PubSub.SubscriptionHandler.Errors.self) { try promise.futureResult.wait() }
    }

    @Test func asyncUnsubscribeSurfacesTheServicesError() async {
        let pubsub = MockPubSub(eventLoop: EmbeddedEventLoop(), unsubscribeResult: .failure(ServiceError()))
        let handler = PubSub.SubscriptionHandler(pubSub: pubsub, topic: "news")

        await #expect(throws: ServiceError()) { try await handler.unsubscribe() }
    }

    @Test func onRoundTrips() throws {
        let loop = EmbeddedEventLoop()
        let pubsub = MockPubSub(eventLoop: loop)
        let handler = PubSub.SubscriptionHandler(pubSub: pubsub, topic: "news")
        #expect(handler.on == nil)

        let received = NIOLockedValueBox<[String]>([])
        handler.on = { event in
            received.withLockedValue { $0.append(event.rawValue) }
            return loop.makeSucceededVoidFuture()
        }
        try handler.on?(.newPeer(PeerID(.Ed25519))).wait()
        #expect(received.withLockedValue { $0 } == ["newPeer"])

        handler.on = nil
        #expect(handler.on == nil)
    }

    /// The handler is `Sendable`, it can be shared across tasks while one side swaps `on` and the
    /// others invoke it.
    @Test func onCanBeSetAndInvokedConcurrently() async throws {
        let loop = EmbeddedEventLoop()
        let pubsub = MockPubSub(eventLoop: loop)
        let handler = PubSub.SubscriptionHandler(pubSub: pubsub, topic: "news")
        let invocations = ManagedAtomicCounter()
        // EmbeddedEventLoop isn't thread-safe, so build the future once here, not inside the closures.
        let done = loop.makeSucceededVoidFuture()

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for _ in 0..<1_000 {
                    handler.on = { _ in
                        invocations.increment()
                        return done
                    }
                    handler.on = nil
                }
            }
            for _ in 0..<4 {
                group.addTask {
                    for _ in 0..<1_000 {
                        _ = handler.on?(.error(ServiceError()))
                    }
                }
            }
        }

        handler.on = { _ in
            invocations.increment()
            return done
        }
        let before = invocations.value
        _ = handler.on?(.error(ServiceError()))
        #expect(invocations.value == before + 1)
    }

    final class ManagedAtomicCounter: Sendable {
        private let box = NIOLockedValueBox(0)
        func increment() { box.withLockedValue { $0 += 1 } }
        var value: Int { box.withLockedValue { $0 } }
    }
}
