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

import NIOCore
import NIOConcurrencyHelpers

public typealias Metadata = [String: [UInt8]]

public final class ComprehensivePeer: Sendable {
    public let id: PeerID
    
    public var addresses: Set<Multiaddr> {
        get { _addresses.withLockedValue { $0 } }
        set { _addresses.withLockedValue { $0 = newValue } }
    }
    private let _addresses: NIOLockedValueBox<Set<Multiaddr>>
    
    public var protocols: Set<SemVerProtocol> {
        get { _protocols.withLockedValue { $0 } }
        set { _protocols.withLockedValue { $0 = newValue } }
    }
    private let _protocols: NIOLockedValueBox<Set<SemVerProtocol>>
    
    public var metadata: Metadata {
        get { _metadata.withLockedValue { $0 } }
        set { _metadata.withLockedValue { $0 = newValue } }
    }
    private let _metadata: NIOLockedValueBox<Metadata>
    
    public var records: Set<PeerRecord> {
        get { _records.withLockedValue { $0 } }
        set { _records.withLockedValue { $0 = newValue } }
    }
    private let _records: NIOLockedValueBox<Set<PeerRecord>>

    public init(id: PeerID, addresses: Set<Multiaddr> = [], protocols: Set<SemVerProtocol> = [], metadata: Metadata = [:], records: Set<PeerRecord> = []) {
        self.id = id
        self._addresses = .init(addresses)
        self._protocols = .init(protocols)
        self._metadata = .init(metadata)
        self._records = .init(records)
    }
    
    //public func add(address: Multiaddr) {
    //    self._addresses.withLockedValue { $0.insert(address) }
    //}
    //
    //public func add(protocol: SemVerProtocol) {
    //    self._protocols.withLockedValue { $0.insert(`protocol`) }
    //}
    //
    //public func addMetadata(key: String, value: [UInt8]) {
    //    self._metadata.withLockedValue { $0[key] = value }
    //}
    //
    //public func add(record: PeerRecord) {
    //    self._records.withLockedValue { $0.insert(record) }
    //}
}

extension ComprehensivePeer: CustomStringConvertible {
    public var description: String {
        let header = "--- 👥 \(self.id) 👥 ---"
        return """
            \(header)
            ☎️ Addresses:
            \t- \(self.addresses.map { $0.description }.joined(separator: "\n\t- "))
            📒 Protocols:
            \t- \(self.protocols.map { $0.stringValue }.joined(separator: "\n\t- "))
            ℹ️ MetaData:
            \t- \(self.metadata.map { "\($0.key) - \(String(data: Data($0.value), encoding: .utf8) ?? $0.value.description)" }.joined(separator: "\n\t- "))
            📜 Records:
            \t\(self.records.map { "\($0.description.replacingOccurrences(of: "\n", with: "\n\t"))" }.joined(separator: "\n\t"))
            \(String(repeating: "-", count: header.count + 2))
            """
    }
}

public protocol PeerStore: KeyRepository, AddressRepository, ProtocolRepository, MetadataRepository, RecordRepository, Sendable {
    func all() -> EventLoopFuture<[ComprehensivePeer]>
    func count() -> EventLoopFuture<Int>
    func dump(peer: PeerID)
    func dumpAll()
}

extension PeerStore {

    /// Given a `PeerInfo` object this method adds both the `PeerID` and the associated `Multiaddr`s to the `PeerStore`.
    /// - Parameters:
    ///   - peerInfo: the `PeerInfo` object to store
    ///   - on: An optional `EventLoop` to return on
    /// - Returns: `Void` upon success, or error upon failure
    public func add(peerInfo: PeerInfo, on: EventLoop? = nil) -> EventLoopFuture<Void> {
        self.add(key: peerInfo.peer, on: on).flatMap {
            self.add(addresses: peerInfo.addresses, toPeer: peerInfo.peer, on: on)
        }
    }

    public func getPeerInfo(byID id: String, on: EventLoop? = nil) -> EventLoopFuture<PeerInfo> {
        self.getKey(forPeer: id, on: on).flatMap { key in
            self.getAddresses(forPeer: key, on: on).map { addresses in
                PeerInfo(peer: key, addresses: addresses)
            }
        }
    }
}

public protocol RecordRepository {
    func add(record: PeerRecord, on: EventLoop?) -> EventLoopFuture<Void>
    func getRecords(forPeer peer: PeerID, on: EventLoop?) -> EventLoopFuture<[PeerRecord]>
    func getMostRecentRecord(forPeer peer: PeerID, on: EventLoop?) -> EventLoopFuture<PeerRecord?>
    func trimRecords(forPeer peer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func removeRecords(forPeer peer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
}

public protocol KeyRepository {
    func removeAllKeys(on: EventLoop?) -> EventLoopFuture<Void>
    func add(key: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func remove(key: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func getKey(forPeer: String, on: EventLoop?) -> EventLoopFuture<PeerID>

    //func getPublicKeys()
    //func addPublicKey()
    //func getKeyPairs()
    //func addKeyPair()
    //func getPeers() -> [PeerID]
}

extension KeyRepository {
    public func removeAllKeys(on: EventLoop? = nil) -> EventLoopFuture<Void> {
        removeAllKeys(on: on)
    }
    public func add(key: PeerID, on: EventLoop? = nil) -> EventLoopFuture<Void> {
        add(key: key, on: on)
    }
    public func remove(key: PeerID, on: EventLoop? = nil) -> EventLoopFuture<Void> {
        remove(key: key, on: on)
    }
    public func getKey(forPeer: String, on: EventLoop? = nil) -> EventLoopFuture<PeerID> {
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

    func add(address: Multiaddr, toPeer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func add(addresses: [Multiaddr], toPeer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func remove(address: Multiaddr, fromPeer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func removeAllAddresses(forPeer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func getAddresses(forPeer: PeerID, on: EventLoop?) -> EventLoopFuture<[Multiaddr]>
    func getPeer(byAddress: Multiaddr, on: EventLoop?) -> EventLoopFuture<String>
    func getPeerID(byAddress address: Multiaddr, on: EventLoop?) -> EventLoopFuture<PeerID>
    func getPeerInfo(byAddress address: Multiaddr, on: EventLoop?) -> EventLoopFuture<PeerInfo>
}

extension AddressRepository {
    public func add(address: Multiaddr, toPeer: PeerID, on: EventLoop? = nil) -> EventLoopFuture<Void> {
        add(address: address, toPeer: toPeer, on: on)
    }
    public func add(addresses: [Multiaddr], toPeer: PeerID, on: EventLoop? = nil) -> EventLoopFuture<Void> {
        add(addresses: addresses, toPeer: toPeer, on: on)
    }
    public func remove(address: Multiaddr, fromPeer: PeerID, on: EventLoop? = nil) -> EventLoopFuture<Void> {
        remove(address: address, fromPeer: fromPeer, on: on)
    }
    public func removeAllAddresses(forPeer: PeerID, on: EventLoop? = nil) -> EventLoopFuture<Void> {
        removeAllAddresses(forPeer: forPeer, on: on)
    }
    public func getAddresses(forPeer: PeerID, on: EventLoop? = nil) -> EventLoopFuture<[Multiaddr]> {
        getAddresses(forPeer: forPeer, on: on)
    }
    public func getPeer(byAddress: Multiaddr, on: EventLoop? = nil) -> EventLoopFuture<String> {
        getPeer(byAddress: byAddress, on: on)
    }
}

public protocol ProtocolRepository {
    func removeAllProtocols(forPeer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func add(protocol: SemVerProtocol, toPeer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func add(protocols: [SemVerProtocol], toPeer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func remove(protocol: SemVerProtocol, fromPeer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func remove(protocols: [SemVerProtocol], fromPeer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func getProtocols(forPeer: PeerID, on: EventLoop?) -> EventLoopFuture<[SemVerProtocol]>
    func getPeers(supportingProtocol: SemVerProtocol, on: EventLoop?) -> EventLoopFuture<[String]>  //PeerID
}

extension ProtocolRepository {
    public func removeAllProtocols(forPeer: PeerID, on: EventLoop? = nil) -> EventLoopFuture<Void> {
        removeAllProtocols(forPeer: forPeer, on: on)
    }
    public func add(protocol: SemVerProtocol, toPeer: PeerID, on: EventLoop? = nil) -> EventLoopFuture<Void> {
        add(protocol: `protocol`, toPeer: toPeer, on: on)
    }
    public func add(protocols: [SemVerProtocol], toPeer: PeerID, on: EventLoop? = nil) -> EventLoopFuture<Void> {
        add(protocols: protocols, toPeer: toPeer, on: on)
    }
    public func remove(protocol: SemVerProtocol, fromPeer: PeerID, on: EventLoop? = nil) -> EventLoopFuture<Void> {
        remove(protocol: `protocol`, fromPeer: fromPeer, on: on)
    }
    public func getProtocols(forPeer: PeerID, on: EventLoop? = nil) -> EventLoopFuture<[SemVerProtocol]> {
        getProtocols(forPeer: forPeer, on: on)
    }
    public func getPeers(supportingProtocol: SemVerProtocol, on: EventLoop? = nil) -> EventLoopFuture<[String]> {
        getPeers(supportingProtocol: supportingProtocol, on: on)
    }
}

public struct MetadataBook: Sendable {
    public enum Keys: String, Sendable {
        case AgentVersion = "agentVersion"
        case ProtocolVersion = "protocolVersion"
        case Latency = "latency"
        case LastHandshake = "lastHandshake"
        case ObservedAddress = "observedAddress"
        case Prunable = "prunable"
        case Discovered = "discovered"
    }

    public struct LatencyMetadata: Codable, CustomStringConvertible, Sendable {
        public var streamLatency: UInt64
        public var connectionLatency: UInt64
        public var streamCount: UInt64
        public var connectionCount: UInt64

        public init(
            streamLatency: UInt64 = 0,
            connectionLatency: UInt64 = 0,
            streamCount: UInt64 = 0,
            connectionCount: UInt64 = 0
        ) {
            self.streamLatency = streamLatency
            self.connectionLatency = connectionLatency
            self.streamCount = streamCount
            self.connectionCount = connectionCount
        }

        public mutating func newStreamLatencyValue(_ ping: UInt64) {
            self.streamLatency = ((self.streamLatency * self.streamCount) + ping) / (self.streamCount + 1)
            self.streamCount += 1
        }

        public mutating func newConnectionLatencyValue(_ ping: UInt64) {
            self.connectionLatency =
                ((self.connectionLatency * self.connectionCount) + ping) / (self.connectionCount + 1)
            self.connectionCount += 1
        }

        public var description: String {
            """
            Connections: \(self.connectionLatency/1_000)us averaged over \(self.connectionCount) \(self.connectionCount == 1 ? "ping" : "pings")
            Streams: \(self.streamLatency/1_000)us averaged over \(self.streamCount) \(self.streamCount == 1 ? "ping" : "pings")
            """
        }
    }

    public struct PrunableMetadata: Codable, CustomStringConvertible, Sendable {
        public enum Prunable: UInt8, Codable, Sendable {
            case prunable = 0
            case preferred
            case necessary

            var description: String {
                switch self {
                case .prunable: return "prunable"
                case .preferred: return "preferred"
                case .necessary: return "necessary"
                }
            }
        }

        public init(prunable: Prunable = .prunable) {
            self.prunable = prunable
        }

        public var prunable: Prunable

        public var description: String {
            """
            Peer Importance: \(prunable.description)")
            """
        }
    }
}

public protocol MetadataRepository {
    //var eventLoop:EventLoop { get }

    func removeAllMetadata(forPeer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func add(metaKey: String, data: [UInt8], toPeer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func add(metaKey: MetadataBook.Keys, data: [UInt8], toPeer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func remove(metaKey: String, fromPeer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    //func remove(metaKey:MetadataBook.Keys, fromPeer:PeerID, on:EventLoop?) -> EventLoopFuture<Void>
    func getMetadata(forPeer: PeerID, on: EventLoop?) -> EventLoopFuture<Metadata>
    //func getMetadata(metaKey:String, forPeer:PeerID, on:EventLoop?) -> EventLoopFuture<(key:String, value: [UInt8])>
    //func getMetadata(metaKey:MetadataBook.Keys, forPeer:PeerID, on:EventLoop?) -> EventLoopFuture<(key:String, value: [UInt8])>
}

/// TODO:  Switch from data to Codable, we handle encoding / decoding return typed values when possible...
extension MetadataRepository {
    public func removeAllMetadata(forPeer: PeerID, on: EventLoop? = nil) -> EventLoopFuture<Void> {
        removeAllMetadata(forPeer: forPeer, on: on)
    }
    public func add(metaKey: String, data: [UInt8], toPeer: PeerID, on: EventLoop? = nil) -> EventLoopFuture<Void> {
        add(metaKey: metaKey, data: data, toPeer: toPeer, on: on)
    }
    //    func add<T:Codable>(metaKey:String, data:T, toPeer:PeerID, on:EventLoop? = nil) -> EventLoopFuture<Void> {
    //        do {
    //            let data = try JSONEncoder().encode(data)
    //            return add(metaKey: metaKey, data: data, toPeer: toPeer, on: on)
    //        } catch {
    //            return (on ?? eventloop).makeFailedFuture(error)
    //        }
    //    }
    public func add(
        metaKey: MetadataBook.Keys,
        data: [UInt8],
        toPeer: PeerID,
        on: EventLoop? = nil
    ) -> EventLoopFuture<Void> {
        add(metaKey: metaKey.rawValue, data: data, toPeer: toPeer, on: on)
    }
    public func remove(metaKey: String, fromPeer: PeerID, on: EventLoop? = nil) -> EventLoopFuture<Void> {
        remove(metaKey: metaKey, fromPeer: fromPeer, on: on)
    }
    //func remove(metaKey:MetadataBook.Keys, fromPeer:PeerID, on:EventLoop? = nil) -> EventLoopFuture<Void> {
    //    remove(metaKey: metaKey.rawValue, fromPeer: fromPeer, on: on)
    //}
    public func getMetadata(forPeer: PeerID, on: EventLoop? = nil) -> EventLoopFuture<Metadata> {
        getMetadata(forPeer: forPeer, on: on)
    }
    //func getMetadata(metaKey: String, forPeer:PeerID, on:EventLoop? = nil) -> EventLoopFuture<(key:String, value: [UInt8])> {
    //    getMetadata(metaKey: metaKey, forPeer: forPeer, on: on)
    //}
}
