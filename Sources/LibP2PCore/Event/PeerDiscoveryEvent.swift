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

public enum PeerDiscoveryEvent: Sendable {
    //case ready
    /// Every time a peer is discovered by a discovery service, it emits a peer event with the discovered peers information
    case onPeer(PeerInfo)
    /// If we found an ip address we think is a libp2p peer, but haven't dialed it yet to make sure...
    case onPotentialPeer(Multiaddr)
}
