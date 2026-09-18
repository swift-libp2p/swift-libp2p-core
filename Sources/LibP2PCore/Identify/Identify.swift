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

import Multiaddr
import NIOCore
import PeerID

/// The `IdentifyMessage` struct was removed in 0.6.0
/// Its name shadowed the generated protobuf `IdentifyMessage` that swift-libp2p actually uses.
// public struct IdentifyMessage: Sendable { }

public protocol IdentityManager: Sendable {

    func register()
    func ping(peer: PeerID) -> EventLoopFuture<TimeAmount>
    func ping(addr: Multiaddr) -> EventLoopFuture<TimeAmount>
    //func constructIdentifyMessage(req:Request) throws -> [UInt8]

}

extension IdentityManager {
    public func ping(peer: PeerID) async throws -> TimeAmount {
        try await self.ping(peer: peer).get()
    }

    public func ping(addr: Multiaddr) async throws -> TimeAmount {
        try await self.ping(addr: addr).get()
    }
}
