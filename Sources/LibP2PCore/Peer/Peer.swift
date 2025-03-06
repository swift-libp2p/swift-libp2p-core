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

extension Multiaddr {
    // TODO: Rename this to getPeerID once https://github.com/swift-libp2p/swift-multiaddr/issues/14 is addressed
    func getPeerIDActual() throws -> PeerID {
        guard let cid = self.getPeerID() else {
            throw NSError(domain: "No CID present in Multiaddr", code: 0)
        }
        return try PeerID(cid: cid)
    }
}
