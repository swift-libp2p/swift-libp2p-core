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

import Testing

@testable import LibP2PCore

// These Multiaddr <-> PeerID tests are located here in swift-libp2p-core because
// this is the first package in our stack that depends on the two of them
@Suite("Multiaddr PeerID Tests")
struct MultiaddrPeerIDTests {

    // Make sure we can extract a PeerID from a Multiaddr
    @Test func testGetPeerID() throws {
        // B58 String
        let ma1 = try Multiaddr("/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN")
        let peerID1 = try ma1.getPeerID()

        // B58 String
        let ma2 = try Multiaddr("/ip4/139.178.91.71/tcp/4001/p2p/QmNnooDu7bfjPFoTZYxMNLWUQJyrVwtbZg5gBMjTezGAJN")
        let peerID2 = try ma2.getPeerID()

        // CID String
        let ma3 = try Multiaddr(
            "/dnsaddr/bootstrap.libp2p.io/p2p/bafzbeiagwnqiviaae5aet2zivwhhsorg75x2wka2pu55o7grr23ulx5kxm"
        )
        let peerID3 = try ma3.getPeerID()

        #expect(peerID1 == peerID2)
        #expect(peerID1 == peerID3)

        // Embedded Public Key
        let ma4 = try Multiaddr("/dnsaddr/bootstrap.libp2p.io/p2p/12D3KooWAfPDpPRRRBrmqy9is2zjU5srQ4hKuZitiGmh4NTTpS2d")
        let peerID4 = try ma4.getPeerID()

        #expect(peerID4.type == .isPublic)

        // Throw when no PeerID is present
        #expect(throws: Error.self) { try Multiaddr("/dnsaddr/bootstrap.libp2p.io/").getPeerID() }
    }

    @Test func testGetPeerIDEmbeddedEd25519PublicKey() throws {
        let ma1 = try Multiaddr("/dnsaddr/bootstrap.libp2p.io/p2p/12D3KooWAfPDpPRRRBrmqy9is2zjU5srQ4hKuZitiGmh4NTTpS2d")

        let embeddedKeyInBytes = try BaseEncoding.decode(ma1.getPeerIDString()!, as: .base58btc)
        let peerID1 = try PeerID(fromBytesID: embeddedKeyInBytes.data.byteArray)

        let ma2 = try Multiaddr("/dnsaddr/bootstrap.libp2p.io/p2p/12D3KooWAfPDpPRRRBrmqy9is2zjU5srQ4hKuZitiGmh4NTTpS2d")
        let peerID2 = try ma2.getPeerID()

        #expect(peerID1 == peerID2)
        #expect(peerID1.type == .isPublic)
        #expect(peerID2.type == .isPublic)

        let ma3 = try Multiaddr("/ip4/139.178.91.71/tcp/4001/p2p/QmPoHmYtUt8BU9eiwMYdBfT6rooBnna5fdAZHUaZASGQY8")
        let peerID3 = try ma3.getPeerID()

        #expect(peerID3.type == .idOnly)

        #expect(peerID1 == peerID3)
    }
}
