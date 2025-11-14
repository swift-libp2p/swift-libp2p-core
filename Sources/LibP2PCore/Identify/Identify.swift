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

public struct IdentifyMessage: Sendable {
    var listenAddresses: [Multiaddr]
    var observedAddress: Multiaddr?
    var protocols: [String]
    var publicKey: PeerID?
    var agentVersion: String?
    var protocolVersion: String?
}

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
