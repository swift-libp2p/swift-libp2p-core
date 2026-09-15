//===----------------------------------------------------------------------===//
//
// This source file is part of the swift-libp2p open source project
//
// Copyright (c) 2022-2026 swift-libp2p project authors
// Licensed under MIT
//
// See LICENSE for license information
// See CONTRIBUTORS for the list of swift-libp2p project authors
//
// SPDX-License-Identifier: MIT
//
//===----------------------------------------------------------------------===//

import NIOConcurrencyHelpers
import NIOCore

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
