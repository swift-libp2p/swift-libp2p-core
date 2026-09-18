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

import NIOCore
public import PeerID

public protocol Security {}

public enum SecurityWarnings: Error, Sendable {
    case expectedPeerMismatch
    case skippedRemotePeerValidation
}

//public protocol SecureConnection {
//    var connection:Connection { get }
//    var security:Security { get }
//}

public protocol SecureConnection: Connection {
    var security: Security { get }
}

/// A SecureTransport turns inbound and outbound unauthenticated, plain-text, native connections into authenticated, encrypted connections.
public protocol SecureTransport {
    /// SecureInbound secures an inbound connection.
    /// - Note: If peer is empty, connections from any peer are accepted.
    /// - TODO: Return a SecureConnection instead
    func secureInbound(insecure: Connection, peer: PeerID?) -> EventLoopFuture<Connection>
    //func upgradeConnection(_ conn: Connection, securedPromise: EventLoopPromise<(remotePeerID:PeerID?, warning:SecurityWarning?)>) -> EventLoopFuture<Void> {

    /// SecureOutbound secures an outbound connection.
    func secureOutbound(insecure: Connection, peer: PeerID) -> EventLoopFuture<Connection>
}

// MARK: - Async

extension SecureTransport {
    public func secureInbound(insecure: Connection, peer: PeerID?) async throws -> Connection {
        try await self.secureInbound(insecure: insecure, peer: peer).get()
    }

    public func secureOutbound(insecure: Connection, peer: PeerID) async throws -> Connection {
        try await self.secureOutbound(insecure: insecure, peer: peer).get()
    }
}
