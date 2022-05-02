//
//  PeerDiscoveryEvent.swift
//  
//
//  Created by Brandon Toms on 4/6/22.
//

import Multiaddr

public enum PeerDiscoveryEvent {
    //case ready
    /// Every time a peer is discovered by a discovery service, it emits a peer event with the discovered peers information
    case onPeer(PeerInfo)
    /// If we found an ip address we think is a libp2p peer, but haven't dialed it yet to make sure...
    case onPotentialPeer(Multiaddr)
}
