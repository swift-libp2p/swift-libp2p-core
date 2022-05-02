//
//  DHTCore.swift
//  
//
//  Created by Brandon Toms on 4/17/22.
//

import NIOCore
import PeerID
import CID

public protocol DHTCore:Discovery, EventLoopService {
    static var key:String { get }
    
//    func findPeer(id:PeerID) -> EventLoopFuture<PeerInfo>
//    func findProviders(cid:CID) -> EventLoopFuture<[PeerInfo]>
//    func getClosestPeers(key:String) -> EventLoopFuture<[PeerID]>
//    func getPublicKey(id:PeerID) -> EventLoopFuture<PeerID>
//    func getValue(forKey:String) -> EventLoopFuture<[UInt8]>
//    func ping(peer:PeerID) -> EventLoopFuture<TimeAmount>
//    func provide(key:CID, broadcast:Bool) -> EventLoopFuture<Void>
//    func putValue(forKey:String, value:[UInt8]) -> EventLoopFuture<Void>
//    func searchValue(key:String) -> EventLoopFuture<[UInt8]>
    
}

public protocol DHTRecord {
    var key:Data { get }
    var value:Data { get }
    var author:Data { get }
    var signature:Data { get }
    var timeReceived:String { get }
}

//public enum DHT {
//    /// message Record {
//    /// optional bytes key = 1;
//    /// optional bytes value = 2;
//    /// optional bytes author = 3;
//    /// optional bytes signature = 4;
//    /// optional string timeReceived = 5;
//    ///
//    public struct Record {
//        let key:[UInt8]?
//        let value:[UInt8]?
//        let author:[UInt8]?
//        let signature:[UInt8]?
//        let timeReceived:String?
//    }
//}
