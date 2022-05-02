//
//  Peer.swift
//  
//
//  Created by Brandon Toms on 3/8/22.
//

import PeerID
import Multiaddr

//public protocol KeyPair {
//    var publicKey:PublicKey { get }
//    var privateKey:PrivateKey? { get }
//}
//
//public protocol Peer {
//    var ID:[UInt8] { get }
//    var keyPair:KeyPair? { get }
//
//    var b58String:String { get }
//
//    func extractPublicKey() -> Result<PublicKey, Error>
//}

//public protocol PeerInfo {
//    var peer:PeerID { get }
//    var addr:[Multiaddr] { get }
//}

public struct PeerInfo {
    public let peer:PeerID
    public let addresses:[Multiaddr]
    
    public init(peer:PeerID, addresses:[Multiaddr]) {
        self.peer = peer
        self.addresses = addresses
    }
}

extension PeerID {
    func extractPublicKey() -> PeerID? {
        if self.type == .isPublic || self.type == .isPrivate { return self }
        switch self.keyPair?.keyType {
        case .ed25519:
            return try? PeerID(cid: self.cidString)
        default:
            return nil
        }
    }
}

//extension Multiaddr {
//    func getPeerID() -> PeerID {
//        self.
//    }
//}



//extension PeerID.Key.RawPublicKey: PublicKey { }
