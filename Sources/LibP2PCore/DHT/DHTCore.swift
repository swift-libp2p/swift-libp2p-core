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

import CID
import NIOCore
import PeerID

public protocol DHTCore: Discovery, EventLoopService {
    static var key: String { get }

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

public protocol DHTRecord: Sendable {
    var key: Data { get }
    var value: Data { get }
    var author: Data { get }
    var signature: Data { get }
    var timeReceived: String { get }
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
