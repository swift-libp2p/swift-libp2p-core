//
//  Identify.swift
//  
//
//  Created by Brandon Toms on 4/6/22.
//

import PeerID
import Multiaddr
import NIOCore

public struct IdentifyMessage {
    var listenAddresses:[Multiaddr] = []
    var observedAddress:Multiaddr?
    var protocols:[String] = []
    var publicKey:PeerID?
    var agentVersion:String?
    var protocolVersion:String?
}

public protocol IdentityManager {
    
    func register()
    func ping(peer:PeerID) -> EventLoopFuture<TimeAmount>
    func ping(addr:Multiaddr) -> EventLoopFuture<TimeAmount>
    //func constructIdentifyMessage(req:Request) throws -> [UInt8]
    
}
