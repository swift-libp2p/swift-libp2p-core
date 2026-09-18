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

/// Upgrades a raw `Connection` by negotiating and installing a security module (encryption /
/// authentication) on its channel pipeline.
///
/// Security modules (e.g. noise, plaintext) conform to this protocol to make themselves
/// available during the connection upgrade process.
public protocol SecurityUpgrader {

    /// The security module's unique key descriptor (e.g. `/noise`)
    static var key: String { get }

    /// Installs the security module's channel handlers on `conn`'s pipeline at `position`,
    /// completing `securedPromise` with the negotiated result (security codec, authenticated
    /// remote peer, and any warnings) once the handshake finishes.
    func upgradeConnection(
        _ conn: Connection,
        position: ChannelPipeline.Position,
        securedPromise: EventLoopPromise<Connection.SecuredResult>
    ) -> EventLoopFuture<Void>

    func printSelf()
}
