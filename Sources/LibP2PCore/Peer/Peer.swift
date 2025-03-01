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
import PeerID

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
    public let peer: PeerID
    public let addresses: [Multiaddr]

    public init(peer: PeerID, addresses: [Multiaddr]) {
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
