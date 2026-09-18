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

public import Foundation
public import Multiaddr
public import PeerID

/// The verdict a `ConnectionGater` returns at each intercept point.
public enum ConnectionGateDecision: Sendable {
    /// Allow the connection to proceed.
    case allow
    /// Deny the connection. The reason is logged and surfaced as the error that fails the
    /// dial / closes the channel.
    case deny(reason: String)

    public var isAllowed: Bool {
        if case .allow = self { return true }
        return false
    }
}

/// What we know before any socket is opened.
///
/// Outgoing dials only
public struct DialGateContext: Sendable {
    public let remoteAddress: Multiaddr
    /// Extracted from the `/p2p` component of `remoteAddress`, when present.
    public let expectedRemotePeer: PeerID?

    public init(
        remoteAddress: Multiaddr,
        expectedRemotePeer: PeerID?
    ) {
        self.remoteAddress = remoteAddress
        self.expectedRemotePeer = expectedRemotePeer
    }
}

/// What we know the moment a transport hands us a connection (an inbound accept or an outbound
/// socket-connected), before the security handshake has run.
public struct RawConnectionGateContext: Sendable {
    public let connectionID: UUID
    public let direction: ConnectionStats.Direction
    public let remoteAddress: Multiaddr
    public let localAddress: Multiaddr?
    /// The number of connections the manager currently holds.
    ///
    /// - Note: This does not include the connection being gated, which is only registered
    ///   with the manager once it is admitted.
    public let currentConnectionCount: Int

    public init(
        connectionID: UUID,
        direction: ConnectionStats.Direction,
        remoteAddress: Multiaddr,
        localAddress: Multiaddr?,
        currentConnectionCount: Int
    ) {
        self.connectionID = connectionID
        self.direction = direction
        self.remoteAddress = remoteAddress
        self.localAddress = localAddress
        self.currentConnectionCount = currentConnectionCount
    }
}

/// What we know once the security handshake has authenticated the remote peer.
public struct SecuredConnectionGateContext: Sendable {
    public let connectionID: UUID
    public let direction: ConnectionStats.Direction
    public let remoteAddress: Multiaddr
    public let remotePeer: PeerID
    /// The security protocol that authenticated the remote peer (e.g. `/noise`).
    public let securityCodec: String

    public init(
        connectionID: UUID,
        direction: ConnectionStats.Direction,
        remoteAddress: Multiaddr,
        remotePeer: PeerID,
        securityCodec: String
    ) {
        self.connectionID = connectionID
        self.direction = direction
        self.remoteAddress = remoteAddress
        self.remotePeer = remotePeer
        self.securityCodec = securityCodec
    }
}

/// Decides which connections this host is willing to dial, accept, and keep.
///
/// - Note: Peer-identity gating (the secured hook) is only consulted by `Connection`
///   implementations that participate in gating, the dial and accept hooks are consulted before a
///   `Connection` implementation is involved, so they always apply.
public protocol ConnectionGater: Sendable {
    /// Consulted before a transport dials `remoteAddress`.
    ///
    /// A `.deny` costs nothing on the wire and fails every dial coalesced onto this address.
    func shouldDial(_ context: DialGateContext) async -> ConnectionGateDecision

    /// Consulted when a raw connection materializes, before the security handshake.
    ///
    /// A `.deny` closes the channel before any handshake bytes are exchanged.
    /// - For inbound connections this is the accept gate
    /// - For outbound connections it is a last-chance gate after the socket connects.
    ///
    /// - Note: This call blocks the connection from being configured, so keep it quick / lite.
    func shouldAcceptRawConnection(_ context: RawConnectionGateContext) async -> ConnectionGateDecision

    /// Consulted after the security handshake, once the remote peer is authenticated.
    ///
    /// A `.deny` closes the channel before the muxer is negotiated.
    func shouldAllowSecuredConnection(_ context: SecuredConnectionGateContext) async -> ConnectionGateDecision
}

extension ConnectionGater {
    public func shouldDial(_ context: DialGateContext) async -> ConnectionGateDecision {
        .allow
    }

    public func shouldAcceptRawConnection(_ context: RawConnectionGateContext) async -> ConnectionGateDecision {
        .allow
    }

    public func shouldAllowSecuredConnection(_ context: SecuredConnectionGateContext) async -> ConnectionGateDecision {
        .allow
    }
}

/// The default, allow-everything, connection gater.
public actor AllowAllConnectionGater: ConnectionGater {
    public init() {}
}
