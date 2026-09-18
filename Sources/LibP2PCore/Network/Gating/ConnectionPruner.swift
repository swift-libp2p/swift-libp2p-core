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
import Multiaddr
import NIOCore
import PeerID

/// A connection's observable liveness.
///
/// - Note: Keyed by `id`, since connection UUIDs are globally unique (unlike muxer stream IDs,
///   which are only unique per direction).
public struct ConnectionLivenessSnapshot: Sendable {
    public let id: UUID
    /// The authenticated remote peer, or `nil` while the connection is still upgrading.
    public let remotePeer: PeerID?
    /// The remoteAddress of the connection, or `nil` if it's being established.
    public let remoteAddress: Multiaddr?
    /// The direction of this Connection (inbound or outbound).
    public let direction: ConnectionStats.Direction
    /// The current status of this Connection.
    public let status: ConnectionStats.Status
    /// When the channel became active.
    public let openedAt: Date
    /// When security + muxer negotiation finished, or `nil` while still upgrading.
    public let upgradedAt: Date?
    /// The number of muxed streams currently open on this connection.
    public let streamCount: Int
    /// When the connection last saw meaningful activity, or `nil` for `Connection`
    /// implementations that don't track activity, such connections are never idle-pruned.
    public let lastActivityAt: Date?

    public init(
        id: UUID,
        remotePeer: PeerID?,
        remoteAddress: Multiaddr?,
        direction: ConnectionStats.Direction,
        status: ConnectionStats.Status,
        openedAt: Date,
        upgradedAt: Date?,
        streamCount: Int,
        lastActivityAt: Date?
    ) {
        self.id = id
        self.remotePeer = remotePeer
        self.remoteAddress = remoteAddress
        self.direction = direction
        self.status = status
        self.openedAt = openedAt
        self.upgradedAt = upgradedAt
        self.streamCount = streamCount
        self.lastActivityAt = lastActivityAt
    }
}

/// Manager-level pressure, so a pruner can scale its aggressiveness with load.
public struct ConnectionPruneContext: Sendable {
    /// The manager's connection limit.
    public let maxConnections: Int
    /// The number of connections currently registered with the manager.
    public let currentConnectionCount: Int
    /// The slice of `maxConnections` reserved for outbound dials (inbound connections are
    /// refused once `maxConnections - inboundBuffer` is reached).
    public let inboundBuffer: Int

    public init(
        maxConnections: Int,
        currentConnectionCount: Int,
        inboundBuffer: Int
    ) {
        self.maxConnections = maxConnections
        self.currentConnectionCount = currentConnectionCount
        self.inboundBuffer = inboundBuffer
    }
}

/// How a connection should be evicted.
public enum ConnectionPruneAction: Sendable {
    /// The connection has already finished closing, just unregister it.
    case unregister
    /// Gracefully close the connection (which also closes its streams), then unregister it.
    case close
}

/// Decides which of a manager's connections should be evicted.
///
/// The ConnectionPruner operates on a snapshot of the manager's connections so one instance can
/// serve any `ConnectionManager`.
public protocol ConnectionPruner: Sendable {
    /// How often the manager should proactively sweep, in addition to its event-driven prunes.
    /// `nil` disables periodic sweeping.
    var sweepInterval: TimeAmount? { get }

    /// Given every managed connection, return only those that should be evicted.
    ///
    /// Connections absent from the returned dictionary are kept.
    func prune(
        _ connections: [ConnectionLivenessSnapshot],
        context: ConnectionPruneContext,
        now: Date
    ) async -> [UUID: ConnectionPruneAction]
}

/// Never prunes, and never asks to be scheduled.
public actor NoOpConnectionPruner: ConnectionPruner {
    public init() {}

    public nonisolated var sweepInterval: TimeAmount? { nil }

    public func prune(
        _ connections: [ConnectionLivenessSnapshot],
        context: ConnectionPruneContext,
        now: Date
    ) async -> [UUID: ConnectionPruneAction] {
        [:]
    }
}

/// Evicts connections that have stopped being useful, more aggressively the fuller the manager is.
///
/// Two failure modes, in priority order:
/// 1. **Already finished.** `.closed` connections that havent been clear yet, unregister them.
/// 2. **Idle.** Connections whose last activity is older than a load-scaled window, an empty
///    manager tolerates ``Configuration/maxExpiration`` of silence, a saturated one only
///    ``Configuration/minExpiration``.
///
/// Connections that don't report activity (`lastActivityAt == nil`) are never idle-pruned.
public actor LoadScaledConnectionPruner: ConnectionPruner {

    public struct Configuration: Sendable {
        /// How long an idle connection survives when the manager is saturated.
        public var minExpiration: TimeAmount = .seconds(3)

        /// How long an idle connection survives when the manager is empty.
        public var maxExpiration: TimeAmount = .seconds(30)

        /// How often the owning manager should sweep. `nil` keeps pruning purely event-driven.
        public var sweepInterval: TimeAmount? = nil

        public init(
            minExpiration: TimeAmount = .seconds(3),
            maxExpiration: TimeAmount = .seconds(30),
            sweepInterval: TimeAmount? = nil
        ) {
            self.minExpiration = minExpiration
            self.maxExpiration = maxExpiration
            self.sweepInterval = sweepInterval
        }
    }

    public let configuration: Configuration

    /// Running total of connections this pruner has asked to evict.
    /// Exposed for diagnostics and to let tests assert a sweep actually did something.
    public private(set) var totalPruned: Int = 0

    public init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    /// `nonisolated` because the manager reads it synchronously when scheduling its sweep, and it
    /// only ever reads an immutable `Sendable` `let`.
    public nonisolated var sweepInterval: TimeAmount? { self.configuration.sweepInterval }

    public func prune(
        _ connections: [ConnectionLivenessSnapshot],
        context: ConnectionPruneContext,
        now: Date
    ) async -> [UUID: ConnectionPruneAction] {
        var actions: [UUID: ConnectionPruneAction] = [:]
        for connection in connections {
            if let action = Self.action(
                for: connection,
                context: context,
                now: now,
                configuration: self.configuration
            ) {
                actions[connection.id] = action
            }
        }
        self.totalPruned += actions.count
        return actions
    }

    static func action(
        for connection: ConnectionLivenessSnapshot,
        context: ConnectionPruneContext,
        now: Date,
        configuration: Configuration
    ) -> ConnectionPruneAction? {
        // The connection's closed but it hasn't been cleaned up yet.
        if connection.status == .closed {
            return .unregister
        }

        // Skip connections that don't report activity.
        guard let lastActivityAt = connection.lastActivityAt else { return nil }

        let expiration = Self.getCurrentIdleTimeout(context: context, configuration: configuration)

        // If the connection's been idle longer than expiration, close it...
        return now.timeIntervalSince(lastActivityAt) > expiration ? .close : nil
    }

    // Scale the idle window with load
    // Interpolates between min and max expiration based on the percent of maxConnections consumed
    static func getCurrentIdleTimeout(context: ConnectionPruneContext, configuration: Configuration) -> Double {
        let percentConsumed =
            (Double(context.currentConnectionCount + context.inboundBuffer) / Double(context.maxConnections))
        let factor = max(0.0, min(1.0, 1.0 - percentConsumed))
        return (factor * (configuration.maxExpiration.asSeconds - configuration.minExpiration.asSeconds))
            + configuration.minExpiration.asSeconds
    }
}
