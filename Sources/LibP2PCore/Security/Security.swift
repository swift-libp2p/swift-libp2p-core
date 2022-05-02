//
//  Security.swift
//  
//
//  Created by Brandon Toms on 3/8/22.
//

import NIOCore
import PeerID

public protocol Security { }

public enum SecurityWarnings:Error {
    case expectedPeerMismatch
    case skippedRemotePeerValidation
}

//public protocol SecureConnection {
//    var connection:Connection { get }
//    var security:Security { get }
//}

public protocol SecureConnection: Connection {
    var security:Security { get }
}

/// A SecureTransport turns inbound and outbound unauthenticated, plain-text, native connections into authenticated, encrypted connections.
public protocol SecureTransport {
    /// SecureInbound secures an inbound connection.
    /// - Note: If peer is empty, connections from any peer are accepted.
    /// - TODO: Return a SecureConnection instead
    func secureInbound(insecure:Connection, peer:PeerID?) -> EventLoopFuture<Connection>
    //func upgradeConnection(_ conn: Connection, securedPromise: EventLoopPromise<(remotePeerID:PeerID?, warning:SecurityWarning?)>) -> EventLoopFuture<Void> {
    
    /// SecureOutbound secures an outbound connection.
    func secureOutbound(insecure:Connection, peer:PeerID) -> EventLoopFuture<Connection>
}


public protocol SecurityProtocolInstaller {
    var protocolName:String { get }
    var protocolVersion:String { get }
    
    /// - TODO: Update this to conform to Libp2p Cryptos protocol `secureOutbound()` and `secureInbound()`
    /// Have secureInbound install the appropriate inbound handlers and the secureOutbound install the outbound handlers, kinda strange but at least the verbage will be consistant.
    func installHandlers(on ctx:ChannelHandlerContext, at position:ChannelPipeline.Position, peerID:PeerID, mode:LibP2PCore.Mode, secured:EventLoopPromise<(Bool, PeerID?)>, expectedRemotePeerID:String?) -> EventLoopFuture<Void>
    
    func protocolString() -> String
}

public extension SecurityProtocolInstaller {
    func protocolString() -> String {
        if protocolVersion.isEmpty {
            return "/\(protocolName)"
        } else {
            return "/\(protocolName)/\(protocolVersion)"
        }
    }
    
    func installHandlers(on ctx:ChannelHandlerContext, at position:ChannelPipeline.Position, peerID:PeerID, mode:LibP2PCore.Mode, secured:EventLoopPromise<(Bool, PeerID?)>, expectedRemotePeerID:String? = nil) -> EventLoopFuture<Void> {
        self.installHandlers(on: ctx, at: position, peerID: peerID, mode: mode, secured: secured, expectedRemotePeerID: expectedRemotePeerID)
    }
    
}
