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

/// Upgrades a secured `Connection` by negotiating and installing a stream `Muxer` on its
/// channel pipeline.
///
/// Muxer modules (e.g. mplex, yamux) conform to this protocol to make themselves available
/// during the connection upgrade process.
public protocol MuxerUpgrader {

    /// The muxer's unique key descriptor (e.g. `/yamux/1.0.0`)
    static var key: String { get }

    /// Installs the muxer's channel handlers on `conn`'s pipeline, completing `muxedPromise`
    /// with the live `Muxer` once the upgrade has been completed.
    func upgradeConnection(_ conn: Connection, muxedPromise: EventLoopPromise<Muxer>) -> EventLoopFuture<Void>

    func printSelf()
}
