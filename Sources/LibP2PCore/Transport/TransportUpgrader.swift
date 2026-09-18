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

public import Logging
public import NIOCore

/// Drives protocol negotiation (e.g. multistream-select) when upgrading a raw channel into a
/// full libp2p connection.
public protocol TransportUpgrader {
    func installHandlers(on channel: Channel)

    /// Returns the channel handler(s) responsible for negotiating a single protocol from the set
    /// of `protocols` provided. This can be called multiple times throughout a Connections
    /// upgrade process (security, muxer) and then again for negotiating what protocol a given
    /// Stream will speak.  This upgrader will complete `promise` with the agreed protocol and
    /// any leftover, already-read bytes (that will be passed along the configured pipeline).
    func negotiate(
        protocols: [String],
        mode: Mode,
        logger: Logger,
        promise: EventLoopPromise<(`protocol`: String, leftoverBytes: ByteBuffer?)>
    ) -> [ChannelHandler]

    func printSelf()
}

extension TransportUpgrader {
    public func printSelf() { print(self) }
}
