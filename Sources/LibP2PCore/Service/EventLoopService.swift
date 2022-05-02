//
//  File.swift
//  
//
//  Created by Brandon Toms on 4/6/22.
//

import NIOCore

public protocol EventLoopService {
    var eventLoop:EventLoop { get }
    var state:ServiceLifecycleState { get }
    func start() throws
    func stop() throws
    func heartbeat() -> EventLoopFuture<Void>
}

//internal protocol _EventLoopService {
//    var eventLoop:EventLoop { get }
//}

public extension EventLoopService {
    /// Implement the heartbeat method to receive a callback every X secs in order to perform state managment updates
    ///
    /// - Note: Default heartbeat implementation does nothing, returns immediately.
    func heartbeat() -> EventLoopFuture<Void> {
        return self.eventLoop.makeSucceededVoidFuture()
    }
}

public enum ServiceLifecycleState {
    case starting
    case started
    case stopping
    case stopped
}
