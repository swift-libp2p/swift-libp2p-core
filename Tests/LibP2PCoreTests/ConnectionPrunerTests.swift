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
import NIOCore
import Testing

@testable import LibP2PCore

@Suite("ConnectionPrunerTests")
struct ConnectionPrunerTests {

    /// A distinct id per snapshot.
    static let ids: [UUID] = (0..<8).map { _ in UUID() }

    /// Fixed "now" so every case is deterministic, ages are expressed relative to it.
    static let now = Date(timeIntervalSince1970: 1_700_000_000)

    static func snapshot(
        index: Int = 0,
        status: ConnectionStats.Status = .upgraded,
        openedSecondsAgo: TimeInterval = 100,
        upgradedSecondsAgo: TimeInterval? = 99,
        streamCount: Int = 0,
        lastActivitySecondsAgo: TimeInterval? = nil
    ) -> ConnectionLivenessSnapshot {
        ConnectionLivenessSnapshot(
            id: ids[index],
            remotePeer: nil,
            remoteAddress: nil,
            direction: .inbound,
            status: status,
            openedAt: now.addingTimeInterval(-openedSecondsAgo),
            upgradedAt: upgradedSecondsAgo.map { now.addingTimeInterval(-$0) },
            streamCount: streamCount,
            lastActivityAt: lastActivitySecondsAgo.map { now.addingTimeInterval(-$0) }
        )
    }

    /// A context with the manager's stock shape: `inboundBuffer` defaults to 20% of the limit,
    /// matching `BasicInMemoryConnectionManager`.
    static func context(
        maxConnections: Int = 50,
        currentConnectionCount: Int,
        inboundBuffer: Int? = nil
    ) -> ConnectionPruneContext {
        ConnectionPruneContext(
            maxConnections: maxConnections,
            currentConnectionCount: currentConnectionCount,
            inboundBuffer: inboundBuffer ?? Int(Double(maxConnections) * 0.2)
        )
    }

    static let config = LoadScaledConnectionPruner.Configuration()

    // MARK: - Closed connections

    /// A connection that finished closing but is still on the books is unregistered regardless of
    /// how fresh its activity stamp is.
    @Test("Closed connections are always unregistered")
    func testClosedConnectionsAreUnregistered() {
        let action = LoadScaledConnectionPruner.action(
            for: Self.snapshot(status: .closed, lastActivitySecondsAgo: 0),
            context: Self.context(currentConnectionCount: 1),
            now: Self.now,
            configuration: Self.config
        )
        #expect(isUnregister(action))
    }

    // MARK: - Idle connections, load-scaled window

    /// An empty manager (no connections, no reserved inbound buffer) tolerates the full
    /// `maxExpiration` (30s) of silence.
    @Test("An empty manager uses the full idle window")
    func testEmptyManagerUsesMaxExpiration() {
        let context = Self.context(currentConnectionCount: 0, inboundBuffer: 0)

        let stale = LoadScaledConnectionPruner.action(
            for: Self.snapshot(lastActivitySecondsAgo: 31),  // > maxExpiration (30s)
            context: context,
            now: Self.now,
            configuration: Self.config
        )
        #expect(isClose(stale))

        let fresh = LoadScaledConnectionPruner.action(
            for: Self.snapshot(lastActivitySecondsAgo: 29),  // < maxExpiration (30s)
            context: context,
            now: Self.now,
            configuration: Self.config
        )
        #expect(fresh == nil)
    }

    /// A saturated manager shrinks the window all the way down to `minExpiration` (3s).
    @Test("A saturated manager uses the minimum idle window")
    func testSaturatedManagerUsesMinExpiration() {
        let context = Self.context(currentConnectionCount: 50)  // 50 + 10 buffer > 50 max

        let stale = LoadScaledConnectionPruner.action(
            for: Self.snapshot(lastActivitySecondsAgo: 4),  // > minExpiration (3s)
            context: context,
            now: Self.now,
            configuration: Self.config
        )
        #expect(isClose(stale))

        let fresh = LoadScaledConnectionPruner.action(
            for: Self.snapshot(lastActivitySecondsAgo: 2),  // < minExpiration (3s)
            context: context,
            now: Self.now,
            configuration: Self.config
        )
        #expect(fresh == nil)
    }

    /// The window interpolates between the two extremes as the manager fills.
    /// 20 connections + 10 buffer on a 50 limit: factor = 1 - 30/50 = 0.4,
    /// window = 0.4 * (30 - 3) + 3 = 13.8s.
    @Test("The idle window scales with utilization")
    func testWindowScalesWithLoad() {
        let context = Self.context(currentConnectionCount: 20)

        let stale = LoadScaledConnectionPruner.action(
            for: Self.snapshot(lastActivitySecondsAgo: 14),  // > 13.8s
            context: context,
            now: Self.now,
            configuration: Self.config
        )
        #expect(isClose(stale))

        let fresh = LoadScaledConnectionPruner.action(
            for: Self.snapshot(lastActivitySecondsAgo: 13),  // < 13.8s
            context: context,
            now: Self.now,
            configuration: Self.config
        )
        #expect(fresh == nil)
    }

    /// Connections that don't report activity are ignored for the time being.
    @Test("A connection with no activity tracking is never idle-pruned")
    func testActivitylessConnectionIsKept() {
        let action = LoadScaledConnectionPruner.action(
            for: Self.snapshot(openedSecondsAgo: 10_000, lastActivitySecondsAgo: nil),
            context: Self.context(currentConnectionCount: 50),  // even under full pressure
            now: Self.now,
            configuration: Self.config
        )
        #expect(action == nil)
    }

    // MARK: - The actor surface

    @Test("prune returns only the connections that should be evicted")
    func testPruneReturnsOnlyEvictions() async {
        let pruner = LoadScaledConnectionPruner()
        let context = Self.context(currentConnectionCount: 3, inboundBuffer: 0)  // window ≈ 28.4s

        let healthy = Self.snapshot(index: 0, lastActivitySecondsAgo: 1)
        let idle = Self.snapshot(index: 1, lastActivitySecondsAgo: 100)
        let closed = Self.snapshot(index: 2, status: .closed, lastActivitySecondsAgo: 0)

        let actions = await pruner.prune([healthy, idle, closed], context: context, now: Self.now)

        #expect(actions.count == 2)
        #expect(actions[healthy.id] == nil)
        #expect(isClose(actions[idle.id]))
        #expect(isUnregister(actions[closed.id]))
        #expect(await pruner.totalPruned == 2)
    }

    @Test("prune on no connections evicts nothing")
    func testPruneWithNoConnections() async {
        let pruner = LoadScaledConnectionPruner()
        let actions = await pruner.prune(
            [],
            context: Self.context(currentConnectionCount: 0),
            now: Self.now
        )
        #expect(actions.isEmpty)
    }

    @Test("NoOpConnectionPruner never prunes and never asks to be scheduled")
    func testNoOpPruner() async {
        let pruner = NoOpConnectionPruner()
        #expect(pruner.sweepInterval == nil)
        let everything = [
            Self.snapshot(index: 0, status: .closed),
            Self.snapshot(index: 1, openedSecondsAgo: 10_000, lastActivitySecondsAgo: 10_000),
        ]
        let actions = await pruner.prune(
            everything,
            context: Self.context(currentConnectionCount: 50),
            now: Self.now
        )
        #expect(actions.isEmpty)
    }

    // MARK: - Configuration

    /// The default configuration's windows must be internally consistent, and the default pruner
    /// must stay purely event-driven (no sweep).
    @Test("Default configuration windows are internally consistent")
    func testDefaultConfigurationIsInternallyConsistent() {
        let config = LoadScaledConnectionPruner.Configuration()
        #expect(config.minExpiration < config.maxExpiration)
        #expect(config.sweepInterval == nil)
        #expect(LoadScaledConnectionPruner().sweepInterval == nil)
    }

    /// A configured sweep interval is what the manager reads when scheduling.
    @Test("A configured sweep interval is surfaced to the manager")
    func testConfiguredSweepIntervalIsSurfaced() {
        let pruner = LoadScaledConnectionPruner(configuration: .init(sweepInterval: .seconds(5)))
        #expect(pruner.sweepInterval == .seconds(5))
    }

    // MARK: - Helpers

    private func isClose(_ action: ConnectionPruneAction?) -> Bool {
        if case .close = action { return true }
        return false
    }

    private func isUnregister(_ action: ConnectionPruneAction?) -> Bool {
        if case .unregister = action { return true }
        return false
    }
}
