//
//  PeerStore.swift
//  
//
//  Created by Brandon Toms on 3/8/22.
//

import NIOCore

public typealias Metadata = [String:[UInt8]]

public final class ComprehensivePeer {
    public var id:PeerID
    public var addresses:[Multiaddr] = []
    public var protocols:[SemVerProtocol] = []
    public var metadata:Metadata = [:]
    public var records:[PeerRecord] = []
    
    public init(id:PeerID) {
        self.id = id
    }
}

public protocol PeerStore:KeyRepository, AddressRepository, ProtocolRepository, MetadataRepository, RecordRepository {
    func all() -> EventLoopFuture<[ComprehensivePeer]>
    func count() -> EventLoopFuture<Int>
    func dump(peer:PeerID)
    func dumpAll()
}

public extension PeerStore {
    
    /// Given a `PeerInfo` object this method adds both the `PeerID` and the associated `Multiaddr`s to the `PeerStore`.
    /// - Parameters:
    ///   - peerInfo: the `PeerInfo` object to store
    ///   - on: An optional `EventLoop` to return on
    /// - Returns: `Void` upon success, or error upon failure
    func add(peerInfo:PeerInfo, on:EventLoop? = nil) -> EventLoopFuture<Void> {
        self.add(key: peerInfo.peer, on: on).flatMap {
            self.add(addresses: peerInfo.addresses, toPeer: peerInfo.peer, on: on)
        }
    }
    
    func getPeerInfo(byID id:String, on:EventLoop? = nil) -> EventLoopFuture<PeerInfo> {
        self.getKey(forPeer: id, on: on).flatMap { key in
            self.getAddresses(forPeer: key, on: on).map { addresses in
                return PeerInfo(peer: key, addresses: addresses)
            }
        }
    }
}

public protocol RecordRepository {
    func add(record:PeerRecord, on:EventLoop?) -> EventLoopFuture<Void>
    func getRecords(forPeer peer:PeerID, on:EventLoop?) -> EventLoopFuture<[PeerRecord]>
    func getMostRecentRecord(forPeer peer:PeerID, on:EventLoop?) -> EventLoopFuture<PeerRecord?>
    func trimRecords(forPeer peer:PeerID, on:EventLoop?) -> EventLoopFuture<Void>
    func removeRecords(forPeer peer:PeerID, on: EventLoop?) -> EventLoopFuture<Void>
}

public protocol KeyRepository {
    func removeAllKeys(on:EventLoop?) -> EventLoopFuture<Void>
    func add(key:PeerID, on:EventLoop?) -> EventLoopFuture<Void>
    func remove(key:PeerID, on:EventLoop?) -> EventLoopFuture<Void>
    func getKey(forPeer:String, on:EventLoop?) -> EventLoopFuture<PeerID>
    
    //func getPublicKeys()
    //func addPublicKey()
    //func getKeyPairs()
    //func addKeyPair()
    //func getPeers() -> [PeerID]
}

public extension KeyRepository {
    func removeAllKeys(on:EventLoop? = nil) -> EventLoopFuture<Void> {
        removeAllKeys(on: on)
    }
    func add(key:PeerID, on:EventLoop? = nil) -> EventLoopFuture<Void> {
        add(key: key, on: on)
    }
    func remove(key:PeerID, on:EventLoop? = nil) -> EventLoopFuture<Void> {
        remove(key: key, on: on)
    }
    func getKey(forPeer:String, on:EventLoop? = nil) -> EventLoopFuture<PeerID> {
        getKey(forPeer: forPeer, on: on)
    }
}

public protocol AddressRepository {
    /// Emits:
    /// - onAddressAdded
    /// - onAddressRemoved
    
    //func addAddresses() -> Bool
    //func upsertAddresses() -> Bool
    //func updateAddresses() -> Bool
    //func getAddresses() -> [Multiaddr]
    //func clear() -> Bool
    //func getPeers() -> [PeerID]
    
    func add(address:Multiaddr, toPeer:PeerID, on:EventLoop?) -> EventLoopFuture<Void>
    func add(addresses:[Multiaddr], toPeer:PeerID, on:EventLoop?) -> EventLoopFuture<Void>
    func remove(address:Multiaddr, fromPeer:PeerID, on:EventLoop?) -> EventLoopFuture<Void>
    func removeAllAddresses(forPeer:PeerID, on:EventLoop?) -> EventLoopFuture<Void>
    func getAddresses(forPeer:PeerID, on:EventLoop?) -> EventLoopFuture<[Multiaddr]>
    func getPeer(byAddress:Multiaddr, on:EventLoop?) -> EventLoopFuture<String>
    func getPeerID(byAddress address: Multiaddr, on: EventLoop?) -> EventLoopFuture<PeerID>
    func getPeerInfo(byAddress address: Multiaddr, on: EventLoop?) -> EventLoopFuture<PeerInfo>
}

public extension AddressRepository {
    func add(address:Multiaddr, toPeer:PeerID, on:EventLoop? = nil) -> EventLoopFuture<Void> {
        add(address: address, toPeer: toPeer, on: on)
    }
    func add(addresses:[Multiaddr], toPeer:PeerID, on:EventLoop? = nil) -> EventLoopFuture<Void> {
        add(addresses: addresses, toPeer: toPeer, on: on)
    }
    func remove(address:Multiaddr, fromPeer:PeerID, on:EventLoop? = nil) -> EventLoopFuture<Void> {
        remove(address: address, fromPeer: fromPeer, on: on)
    }
    func removeAllAddresses(forPeer:PeerID, on:EventLoop? = nil) -> EventLoopFuture<Void> {
        removeAllAddresses(forPeer: forPeer, on: on)
    }
    func getAddresses(forPeer:PeerID, on:EventLoop? = nil) -> EventLoopFuture<[Multiaddr]> {
        getAddresses(forPeer: forPeer, on: on)
    }
    func getPeer(byAddress:Multiaddr, on:EventLoop? = nil) -> EventLoopFuture<String> {
        getPeer(byAddress: byAddress, on: on)
    }
}

public protocol ProtocolRepository {
    func removeAllProtocols(forPeer:PeerID, on:EventLoop?) -> EventLoopFuture<Void>
    func add(protocol:SemVerProtocol, toPeer:PeerID, on:EventLoop?) -> EventLoopFuture<Void>
    func add(protocols:[SemVerProtocol], toPeer:PeerID, on:EventLoop?) -> EventLoopFuture<Void>
    func remove(protocol:SemVerProtocol, fromPeer:PeerID, on:EventLoop?) -> EventLoopFuture<Void>
    func remove(protocols:[SemVerProtocol], fromPeer:PeerID, on:EventLoop?) -> EventLoopFuture<Void>
    func getProtocols(forPeer:PeerID, on:EventLoop?) -> EventLoopFuture<[SemVerProtocol]>
    func getPeers(supportingProtocol:SemVerProtocol, on:EventLoop?) -> EventLoopFuture<[String]> //PeerID
}

public extension ProtocolRepository {
    func removeAllProtocols(forPeer:PeerID, on:EventLoop? = nil) -> EventLoopFuture<Void> {
        removeAllProtocols(forPeer: forPeer, on: on)
    }
    func add(protocol:SemVerProtocol, toPeer:PeerID, on:EventLoop? = nil) -> EventLoopFuture<Void> {
        add(protocol: `protocol`, toPeer: toPeer, on: on)
    }
    func add(protocols:[SemVerProtocol], toPeer:PeerID, on:EventLoop? = nil) -> EventLoopFuture<Void> {
        add(protocols: protocols, toPeer: toPeer, on: on)
    }
    func remove(protocol:SemVerProtocol, fromPeer:PeerID, on:EventLoop? = nil) -> EventLoopFuture<Void> {
        remove(protocol: `protocol`, fromPeer: fromPeer, on: on)
    }
    func getProtocols(forPeer:PeerID, on:EventLoop? = nil) -> EventLoopFuture<[SemVerProtocol]> {
        getProtocols(forPeer: forPeer, on: on)
    }
    func getPeers(supportingProtocol:SemVerProtocol, on:EventLoop? = nil) -> EventLoopFuture<[String]> {
        getPeers(supportingProtocol: supportingProtocol, on: on)
    }
}

public struct MetadataBook {
    public enum Keys:String {
        case AgentVersion    = "agentVersion"
        case ProtocolVersion = "protocolVersion"
        case Latency         = "latency"
        case LastHandshake   = "lastHandshake"
        case ObservedAddress = "observedAddress"
        case Prunable        = "prunable"
    }
    
    public struct LatencyMetadata:Codable, CustomStringConvertible {
        public var streamLatency:UInt64
        public var connectionLatency:UInt64
        public var streamCount:UInt64
        public var connectionCount:UInt64
        
        public init(streamLatency:UInt64 = 0, connectionLatency:UInt64 = 0, streamCount:UInt64 = 0, connectionCount:UInt64 = 0) {
            self.streamLatency = streamLatency
            self.connectionLatency = connectionLatency
            self.streamCount = streamCount
            self.connectionCount = connectionCount
        }
        
        public mutating func newStreamLatencyValue(_ ping:UInt64) {
            self.streamLatency = ((self.streamLatency * self.streamCount) + ping) / (self.streamCount + 1)
            self.streamCount += 1
        }
        
        public mutating func newConnectionLatencyValue(_ ping:UInt64) {
            self.connectionLatency = ((self.connectionLatency * self.connectionCount) + ping) / (self.connectionCount + 1)
            self.connectionCount += 1
        }
        
        public var description: String {
            """
            Connections: \(self.connectionLatency/1_000)us averaged over \(self.connectionCount) \(self.connectionCount == 1 ? "ping" : "pings")
            Streams: \(self.streamLatency/1_000)us averaged over \(self.streamCount) \(self.streamCount == 1 ? "ping" : "pings")
            """
        }
    }
    
    public struct PrunableMetadata:Codable, CustomStringConvertible {
        public enum Prunable:UInt8, Codable {
            case prunable = 0
            case preferred
            case necessary
            
            var description:String {
                switch self {
                case .prunable:  return "prunable"
                case .preferred: return "preferred"
                case .necessary: return "necessary"
                }
            }
        }
        
        public init(prunable:Prunable = .prunable) {
            self.prunable = prunable
        }
        
        public var prunable:Prunable
        
        public var description: String {
            """
            Peer Importance: \(prunable.description)")
            """
        }
    }
}

public protocol MetadataRepository {
    func removeAllMetadata(forPeer:PeerID, on:EventLoop?) -> EventLoopFuture<Void>
    func add(metaKey:String, data:[UInt8], toPeer:PeerID, on:EventLoop?) -> EventLoopFuture<Void>
    func add(metaKey:MetadataBook.Keys, data:[UInt8], toPeer:PeerID, on:EventLoop?) -> EventLoopFuture<Void>
    func remove(metaKey:String, fromPeer:PeerID, on:EventLoop?) -> EventLoopFuture<Void>
    func getMetadata(forPeer:PeerID, on:EventLoop?) -> EventLoopFuture<Metadata>
}

public extension MetadataRepository {
    func removeAllMetadata(forPeer:PeerID, on:EventLoop? = nil) -> EventLoopFuture<Void> {
        removeAllMetadata(forPeer: forPeer, on: on)
    }
    func add(metaKey:String, data:[UInt8], toPeer:PeerID, on:EventLoop? = nil) -> EventLoopFuture<Void> {
        add(metaKey: metaKey, data: data, toPeer: toPeer, on: on)
    }
    func add(metaKey:MetadataBook.Keys, data:[UInt8], toPeer:PeerID, on:EventLoop? = nil) -> EventLoopFuture<Void> {
        add(metaKey: metaKey.rawValue, data: data, toPeer: toPeer, on: on)
    }
    func remove(metaKey:String, fromPeer:PeerID, on:EventLoop? = nil) -> EventLoopFuture<Void> {
        remove(metaKey: metaKey, fromPeer: fromPeer, on: on)
    }
    func getMetadata(forPeer:PeerID, on:EventLoop? = nil) -> EventLoopFuture<Metadata> {
        getMetadata(forPeer: forPeer, on: on)
    }
}
