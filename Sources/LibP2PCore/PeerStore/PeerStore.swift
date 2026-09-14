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

import Foundation
import NIOConcurrencyHelpers
import NIOCore

public typealias Metadata = [String: [UInt8]]

/// Everything we know about this peer
///
/// `ComprehensivePeer` includes the following:
/// - Their `PeerID` (public key)
/// - Known addresses
/// - Supported protocols
/// - Arbitrary metadata
/// - Signed `PeerRecord`s
///
/// - Note: Changes made to this object do NOT propogate back to the peerstore
///   Use the dedicated peerstore methods to persist changes.
public final class ComprehensivePeer: Sendable {
    public let id: PeerID

    /// The mutable state of a `ComprehensivePeer`, guarded by a single lock so that composite
    /// reads are consistent.
    fileprivate struct State: Sendable {
        var addresses: Set<Multiaddr>
        var protocols: Set<SemVerProtocol>
        var metadata: Metadata
        var records: Set<PeerRecord>
    }

    private let state: NIOLockedValueBox<State>

    
    /// The addresses associated with this peer
    ///
    /// - Note: Consider using  the ``insert(address:)``/ ``remove(address:)``
    ///   functions instead of setting this parameter directly
    public var addresses: Set<Multiaddr> {
        get { self.state.withLockedValue { $0.addresses } }
        set { self.state.withLockedValue { $0.addresses = newValue } }
    }

    /// The protocols this peer claims to speak
    ///
    /// - Note: Consider using  the ``insert(protocol:)``/ ``remove(protocol:)``
    ///   functions instead of setting this parameter directly
    public var protocols: Set<SemVerProtocol> {
        get { self.state.withLockedValue { $0.protocols } }
        set { self.state.withLockedValue { $0.protocols = newValue } }
    }

    /// The Metadata associated with this peer
    ///
    /// - Note: Consider using  the ``setMetadata(:, forKey:)``/ ``metadata(forKey:)``
    ///   functions instead of setting this parameter directly
    public var metadata: Metadata {
        get { self.state.withLockedValue { $0.metadata } }
        set { self.state.withLockedValue { $0.metadata = newValue } }
    }

    /// The signed Records we have for this Peer
    ///
    /// - Note: Consider using  the ``insert(record:, keepingMostRecent:)``
    ///   function instead of setting this parameter directly
    public var records: Set<PeerRecord> {
        get { self.state.withLockedValue { $0.records } }
        set { self.state.withLockedValue { $0.records = newValue } }
    }

    public init(
        id: PeerID,
        addresses: Set<Multiaddr> = [],
        protocols: Set<SemVerProtocol> = [],
        metadata: Metadata = [:],
        records: Set<PeerRecord> = []
    ) {
        self.id = id
        self.state = .init(
            State(addresses: addresses, protocols: protocols, metadata: metadata, records: records)
        )
    }

    /// Inserts an address, returning `true` if it wasn't already known.
    @discardableResult
    public func insert(address: Multiaddr) -> Bool {
        self.state.withLockedValue { $0.addresses.insert(address).inserted }
    }

    /// Inserts a batch of addresses in a single atomic operation.
    public func insert(addresses: some Sequence<Multiaddr>) {
        self.state.withLockedValue { $0.addresses.formUnion(addresses) }
    }

    /// Removes an address, returning it if there was a match.
    @discardableResult
    public func remove(address: Multiaddr) -> Multiaddr? {
        self.state.withLockedValue { $0.addresses.remove(address) }
    }

    /// Removes all addresses from this peer
    public func removeAllAddresses() {
        self.state.withLockedValue { $0.addresses.removeAll() }
    }

    /// Inserts a protocol, returning `true` if it wasn't already known.
    @discardableResult
    public func insert(protocol proto: SemVerProtocol) -> Bool {
        self.state.withLockedValue { $0.protocols.insert(proto).inserted }
    }

    /// Inserts a batch of protocols in a single atomic operation.
    public func insert(protocols: some Sequence<SemVerProtocol>) {
        self.state.withLockedValue { $0.protocols.formUnion(protocols) }
    }

    /// Removes a protocol, returning it if there was a match.
    @discardableResult
    public func remove(protocol proto: SemVerProtocol) -> SemVerProtocol? {
        self.state.withLockedValue { $0.protocols.remove(proto) }
    }

    /// Removes a batch of protocols in a single atomic operation
    public func remove(protocols: some Sequence<SemVerProtocol>) {
        self.state.withLockedValue { $0.protocols.subtract(protocols) }
    }

    /// Removes all protocols from this peer
    public func removeAllProtocols() {
        self.state.withLockedValue { $0.protocols.removeAll() }
    }

    /// Sets (or, when `value` is `nil`, removes) a single metadata entry.
    public func setMetadata(_ value: [UInt8]?, forKey key: String) {
        self.state.withLockedValue { $0.metadata[key] = value }
    }

    /// Reads a single metadata entry.
    public func metadata(forKey key: String) -> [UInt8]? {
        self.state.withLockedValue { $0.metadata[key] }
    }

    /// Removes all metadata from this peer
    public func removeAllMetadata() {
        self.state.withLockedValue { $0.metadata.removeAll() }
    }

    /// Inserts a `PeerRecord`, then keeps the most `limit` recent records.
    ///
    /// Records are considered duplicates when they share a sequence number.
    ///
    /// - Returns: `true` if the record was new, `false` if a record with that sequence number was
    ///   already present or if the record was older than the existing `limit` records.
    @discardableResult
    public func insert(record: PeerRecord, keepingMostRecent limit: Int) -> Bool {
        self.state.withLockedValue { state in
            guard !state.records.contains(where: { $0.sequenceNumber == record.sequenceNumber }) else {
                return false
            }
            state.records.insert(record)
            Self.trim(&state.records, keepingMostRecent: limit)
            return state.records.contains(record)
        }
    }

    /// Trims the record set down to the `limit` most recent records (by sequence number).
    public func trimRecords(keepingMostRecent limit: Int) {
        self.state.withLockedValue { Self.trim(&$0.records, keepingMostRecent: limit) }
    }

    /// Removes all of the records associated with this peer.
    public func removeAllRecords() {
        self.state.withLockedValue { $0.records.removeAll() }
    }

    private static func trim(_ records: inout Set<PeerRecord>, keepingMostRecent limit: Int) {
        guard limit >= 0 else { return }
        guard records.count > limit else { return }
        records = Set(
            records.sorted { $0.sequenceNumber > $1.sequenceNumber }.prefix(limit)
        )
    }

    /// Returns a detached copy of this peer, taken under a single lock acquisition.
    ///
    /// Use this when handing a peer out across an API boundary so callers can't mutate the
    /// store's live state behind its back.
    public func copy() -> ComprehensivePeer {
        let state = self.state.withLockedValue { $0 }
        return ComprehensivePeer(
            id: self.id,
            addresses: state.addresses,
            protocols: state.protocols,
            metadata: state.metadata,
            records: state.records
        )
    }

    /// The peer's `PeerID` paired with its currently known addresses.
    public var peerInfo: PeerInfo {
        PeerInfo(peer: self.id, addresses: Array(self.addresses))
    }
}

extension ComprehensivePeer: CustomStringConvertible {
    public var description: String {
        let state = self.state.withLockedValue { $0 }
        let header = "--- 👥 \(self.id) 👥 ---"
        return """
            \(header)
            ☎️ Addresses:
            \t- \(state.addresses.map { $0.description }.joined(separator: "\n\t- "))
            📒 Protocols:
            \t- \(state.protocols.map { $0.stringValue }.joined(separator: "\n\t- "))
            ℹ️ MetaData:
            \t- \(state.metadata.map { "\($0.key) - \(String(data: Data($0.value), encoding: .utf8) ?? $0.value.description)" }.joined(separator: "\n\t- "))
            📜 Records:
            \t\(state.records.map { "\($0.description.replacingOccurrences(of: "\n", with: "\n\t"))" }.joined(separator: "\n\t"))
            \(String(repeating: "-", count: header.count + 2))
            """
    }
}

public protocol PeerStore: KeyRepository, AddressRepository, ProtocolRepository, MetadataRepository, RecordRepository,
    Sendable
{
    /// Returns a collection of every peer in the PeerStore
    ///
    /// - Warning: This can be slow and resource heavy if the peerstore contains a large
    ///   number of peers.
    func all() -> EventLoopFuture<[ComprehensivePeer]>
    
    /// Returns the number of Peers that are currently stored in the PeerStore
    func count() -> EventLoopFuture<Int>
    
    /// Logs the specified peer to the console
    func dump(peer: PeerID)
    
    /// Logs the entire PeerStore to the console
    func dumpAll()

    /// Every `PeerID` currently held by the store.
    func getAllPeerIDs(on: EventLoop?) -> EventLoopFuture<[PeerID]>

    /// Every peer currently held by the store, paired with their known addresses.
    func getAllPeerInfos(on: EventLoop?) -> EventLoopFuture<[PeerInfo]>

    /// The `PeerID`s of every peer known to support `supportingProtocol` **exactly**.
    func getPeerIDs(supportingProtocol: SemVerProtocol, on: EventLoop?) -> EventLoopFuture<[PeerID]>

    /// The b58 identifiers of every peer supporting a protocol *compatible* with
    /// `matchingProtocol`, using ``SemVerProtocol/matches(_:)`` semantics.
    func getPeers(matchingProtocol: SemVerProtocol, on: EventLoop?) -> EventLoopFuture<[String]>

    /// The `PeerID`s of every peer supporting a protocol *compatible* with
    /// `matchingProtocol`,  using ``SemVerProtocol/matches(_:)`` semantics.
    func getPeerIDs(matchingProtocol: SemVerProtocol, on: EventLoop?) -> EventLoopFuture<[PeerID]>
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

    /// Given a `PeerInfo` object this method adds both the `PeerID` and the associated `Multiaddr`s to the `PeerStore`.
    /// - Parameters:
    ///   - peerInfo: the `PeerInfo` object to store
    ///   - on: An optional `EventLoop` to return on
    /// - Returns: `Void` upon success, or error upon failure
    public func add(peerInfo: PeerInfo, on: EventLoop? = nil) async throws {
        try await self.add(peerInfo: peerInfo, on: on).get()
    }

    public func getPeerInfo(byID id: String, on: EventLoop? = nil) -> EventLoopFuture<PeerInfo> {
        self.getKey(forPeer: id, on: on).flatMap { key in
            self.getAddresses(forPeer: key, on: on).map { addresses in
                PeerInfo(peer: key, addresses: addresses)
            }
        }
    }

    public func getPeerInfo(byID id: String, on: EventLoop? = nil) async throws -> PeerInfo {
        try await self.getPeerInfo(byID: id, on: on).get()
    }

    public func getAllPeerIDs(on: EventLoop?) -> EventLoopFuture<[PeerID]> {
        self.all().map { peers in peers.map { $0.id } }.hopIfNeeded(to: on)
    }

    public func getAllPeerIDs() -> EventLoopFuture<[PeerID]> {
        self.getAllPeerIDs(on: nil)
    }

    public func getAllPeerInfos(on: EventLoop?) -> EventLoopFuture<[PeerInfo]> {
        self.all().map { peers in peers.map { $0.peerInfo } }.hopIfNeeded(to: on)
    }

    public func getAllPeerInfos() -> EventLoopFuture<[PeerInfo]> {
        self.getAllPeerInfos(on: nil)
    }

    public func getPeerIDs(supportingProtocol proto: SemVerProtocol, on: EventLoop?) -> EventLoopFuture<[PeerID]> {
        self.all().map { peers in
            peers.filter { $0.protocols.contains(proto) }.map { $0.id }
        }.hopIfNeeded(to: on)
    }

    public func getPeerIDs(supportingProtocol proto: SemVerProtocol) -> EventLoopFuture<[PeerID]> {
        self.getPeerIDs(supportingProtocol: proto, on: nil)
    }

    public func getPeers(matchingProtocol proto: SemVerProtocol, on: EventLoop?) -> EventLoopFuture<[String]> {
        self.all().map { peers in
            peers.filter { $0.protocols.contains { $0.matches(proto) } }.map { $0.id.b58String }
        }.hopIfNeeded(to: on)
    }

    public func getPeers(matchingProtocol proto: SemVerProtocol) -> EventLoopFuture<[String]> {
        self.getPeers(matchingProtocol: proto, on: nil)
    }

    public func getPeerIDs(matchingProtocol proto: SemVerProtocol, on: EventLoop?) -> EventLoopFuture<[PeerID]> {
        self.all().map { peers in
            peers.filter { $0.protocols.contains { $0.matches(proto) } }.map { $0.id }
        }.hopIfNeeded(to: on)
    }

    public func getPeerIDs(matchingProtocol proto: SemVerProtocol) -> EventLoopFuture<[PeerID]> {
        self.getPeerIDs(matchingProtocol: proto, on: nil)
    }
}

extension EventLoopFuture {
    /// `hop(to:)` when a destination loop was supplied, otherwise a no-op.
    internal func hopIfNeeded(to eventLoop: EventLoop?) -> EventLoopFuture<Value> {
        guard let eventLoop else { return self }
        return self.hop(to: eventLoop)
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

// MARK: - Async

extension PeerStore {
    public func all() async throws -> [ComprehensivePeer] {
        try await self.all().get()
    }

    public func count() async throws -> Int {
        try await self.count().get()
    }
}

extension KeyRepository {
    public func removeAllKeys() async throws {
        try await self.removeAllKeys(on: nil).get()
    }

    public func add(key: PeerID) async throws {
        try await self.add(key: key, on: nil).get()
    }

    public func remove(key: PeerID) async throws {
        try await self.remove(key: key, on: nil).get()
    }

    public func getKey(forPeer: String) async throws -> PeerID {
        try await self.getKey(forPeer: forPeer, on: nil).get()
    }
}

extension AddressRepository {
    public func add(address: Multiaddr, toPeer: PeerID) async throws {
        try await self.add(address: address, toPeer: toPeer, on: nil).get()
    }

    public func add(addresses: [Multiaddr], toPeer: PeerID) async throws {
        try await self.add(addresses: addresses, toPeer: toPeer, on: nil).get()
    }

    public func remove(address: Multiaddr, fromPeer: PeerID) async throws {
        try await self.remove(address: address, fromPeer: fromPeer, on: nil).get()
    }

    public func removeAllAddresses(forPeer: PeerID) async throws {
        try await self.removeAllAddresses(forPeer: forPeer, on: nil).get()
    }

    public func getAddresses(forPeer: PeerID) async throws -> [Multiaddr] {
        try await self.getAddresses(forPeer: forPeer, on: nil).get()
    }

    public func getPeer(byAddress: Multiaddr) async throws -> String {
        try await self.getPeer(byAddress: byAddress, on: nil).get()
    }

    public func getPeerID(byAddress address: Multiaddr) async throws -> PeerID {
        try await self.getPeerID(byAddress: address, on: nil).get()
    }

    public func getPeerInfo(byAddress address: Multiaddr) async throws -> PeerInfo {
        try await self.getPeerInfo(byAddress: address, on: nil).get()
    }
}

extension ProtocolRepository {
    public func removeAllProtocols(forPeer: PeerID) async throws {
        try await self.removeAllProtocols(forPeer: forPeer, on: nil).get()
    }

    public func add(protocol proto: SemVerProtocol, toPeer: PeerID) async throws {
        try await self.add(protocol: proto, toPeer: toPeer, on: nil).get()
    }

    public func add(protocols: [SemVerProtocol], toPeer: PeerID) async throws {
        try await self.add(protocols: protocols, toPeer: toPeer, on: nil).get()
    }

    public func remove(protocol proto: SemVerProtocol, fromPeer: PeerID) async throws {
        try await self.remove(protocol: proto, fromPeer: fromPeer, on: nil).get()
    }

    public func remove(protocols: [SemVerProtocol], fromPeer: PeerID) async throws {
        try await self.remove(protocols: protocols, fromPeer: fromPeer, on: nil).get()
    }

    public func getProtocols(forPeer: PeerID) async throws -> [SemVerProtocol] {
        try await self.getProtocols(forPeer: forPeer, on: nil).get()
    }

    public func getPeers(supportingProtocol: SemVerProtocol) async throws -> [String] {
        try await self.getPeers(supportingProtocol: supportingProtocol, on: nil).get()
    }
}

extension MetadataRepository {
    public func removeAllMetadata(forPeer: PeerID) async throws {
        try await self.removeAllMetadata(forPeer: forPeer, on: nil).get()
    }

    public func add(metaKey: String, data: [UInt8], toPeer: PeerID) async throws {
        try await self.add(metaKey: metaKey, data: data, toPeer: toPeer, on: nil).get()
    }

    public func add(metaKey: MetadataBook.Keys, data: [UInt8], toPeer: PeerID) async throws {
        try await self.add(metaKey: metaKey, data: data, toPeer: toPeer, on: nil).get()
    }

    public func remove(metaKey: String, fromPeer: PeerID) async throws {
        try await self.remove(metaKey: metaKey, fromPeer: fromPeer, on: nil).get()
    }

    public func getMetadata(forPeer: PeerID) async throws -> Metadata {
        try await self.getMetadata(forPeer: forPeer, on: nil).get()
    }
}

extension RecordRepository {
    public func add(record: PeerRecord) async throws {
        try await self.add(record: record, on: nil).get()
    }

    public func getRecords(forPeer peer: PeerID) async throws -> [PeerRecord] {
        try await self.getRecords(forPeer: peer, on: nil).get()
    }

    public func getMostRecentRecord(forPeer peer: PeerID) async throws -> PeerRecord? {
        try await self.getMostRecentRecord(forPeer: peer, on: nil).get()
    }

    public func trimRecords(forPeer peer: PeerID) async throws {
        try await self.trimRecords(forPeer: peer, on: nil).get()
    }

    public func removeRecords(forPeer peer: PeerID) async throws {
        try await self.removeRecords(forPeer: peer, on: nil).get()
    }
}
