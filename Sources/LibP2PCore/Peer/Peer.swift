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

/// A peer (PeerID) and their known addresses (Multiaddr)
public struct PeerInfo: Sendable {
    public let peer: PeerID
    public let addresses: [Multiaddr]

    public init(peer: PeerID, addresses: [Multiaddr]) {
        self.peer = peer
        self.addresses = addresses
    }
}

extension Multiaddr {
    /// Attempts to extract a PeerID from the Multiaddr if one is present
    /// - Note: The returned PeerID is usually only an ID and doesn't contain a key pair. In some instances (ED25519 keys) a public key might be recoverable.
    public func getPeerID() throws -> PeerID {
        guard let cid = self.getPeerIDString() else {
            throw NSError(domain: "No CID present in Multiaddr", code: 0)
        }
        return try PeerID(cid: cid)
    }
}

extension PeerInfo: CustomStringConvertible {
    public var description: String {
        if self.addresses.isEmpty {
            return self.peer.description
        }
        return """
            \(self.peer) [
            \(self.addresses.map({ $0.description }).joined(separator: "\n") )
            ]
            """
    }
}
