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

import NIOCore

public protocol EventLoopService {
    var eventLoop: EventLoop { get }
    var state: ServiceLifecycleState { get }
    func start() throws
    func stop() throws
    func heartbeat() -> EventLoopFuture<Void>
}

//internal protocol _EventLoopService {
//    var eventLoop:EventLoop { get }
//}

extension EventLoopService {
    /// Implement the heartbeat method to receive a callback every X secs in order to perform state managment updates
    ///
    /// - Note: Default heartbeat implementation does nothing, returns immediately.
    public func heartbeat() -> EventLoopFuture<Void> {
        self.eventLoop.makeSucceededVoidFuture()
    }
}

public enum ServiceLifecycleState: Sendable {
    case starting
    case started
    case stopping
    case stopped
}
