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
        /// The signed envelopes of our PeerRecords (if it exists), keyed by sequence number.
        var envelopes: [UInt64: SealedEnvelope]
    }

    private let state: NIOLockedValueBox<State>

    /// The addresses associated with this peer
    ///
    /// - Note: Mutate through the ``insert(address:)`` / ``remove(address:)``.
    public var addresses: Set<Multiaddr> {
        self.state.withLockedValue { $0.addresses }
    }

    /// The protocols this peer claims to speak
    ///
    /// - Note: Mutate through the ``insert(protocol:)`` / ``remove(protocol:)``.
    public var protocols: Set<SemVerProtocol> {
        self.state.withLockedValue { $0.protocols }
    }

    /// The Metadata associated with this peer
    ///
    /// - Note: Mutate through the ``setMetadata(_:forKey:)`` / ``metadata(forKey:)``.
    public var metadata: Metadata {
        self.state.withLockedValue { $0.metadata }
    }

    /// The signed Records we have for this Peer
    ///
    /// - Note: Mutate through the ``insert(record:keepingMostRecent:)``.
    public var records: Set<PeerRecord> {
        self.state.withLockedValue { $0.records }
    }

    /// The signed envelopes our records arrived in, exactly as the peer signed them, newest first.
    ///
    /// Records added without an envelope (e.g. unsigned or local records) have no entry here.
    ///
    /// - Note: Mutate through the ``insert(signedRecord:keepingMostRecent:)``.
    public var signedRecords: [SealedEnvelope] {
        self.state.withLockedValue { state in
            state.envelopes.sorted { $0.key > $1.key }.map(\.value)
        }
    }

    /// The signed envelope of the most recent record that arrived signed, if any.
    ///
    /// - Note: This can be older than the newest entry in ``records`` when a newer record was
    ///   added without an envelope.
    public var mostRecentSignedRecord: SealedEnvelope? {
        self.state.withLockedValue { state in
            state.envelopes.max { $0.key < $1.key }?.value
        }
    }

    /// - Parameter signedRecords: Envelopes to restore. Each one's record is added to `records`.
    ///   Envelopes that don't carry a valid `PeerRecord` for `id` are skipped.
    public init(
        id: PeerID,
        addresses: Set<Multiaddr> = [],
        protocols: Set<SemVerProtocol> = [],
        metadata: Metadata = [:],
        records: Set<PeerRecord> = [],
        signedRecords: [SealedEnvelope] = []
    ) {
        self.id = id
        var state = State(
            addresses: addresses,
            protocols: protocols,
            metadata: metadata,
            records: records,
            envelopes: [:]
        )
        for envelope in signedRecords {
            guard let record = try? PeerRecord(signedEnvelope: envelope) else { continue }
            _ = Self.insert(record, envelope: envelope, for: id, into: &state, keepingMostRecent: nil)
        }
        self.state = .init(state)
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
            Self.trim(&state, keepingMostRecent: limit)
            return state.records.contains(record)
        }
    }

    /// Inserts the `PeerRecord` carried by `envelope` and keeps the envelope alongside it, then
    /// keeps the most `limit` recent records.
    ///
    /// If a record with the same sequence number was already added without an envelope, and it
    /// matches the envelope's record, the envelope is attached to it.
    ///
    /// - Returns: `true` if the record or its envelope was new. `false` if the envelope is for a
    ///   different peer, if we already have a signed record with that sequence number, if a
    ///   *different* record already has that sequence number, or if the record was older than the
    ///   existing `limit` records.
    /// - Throws: If the envelope doesn't carry a valid `PeerRecord` (see `PeerRecord(signedEnvelope:)`).
    @discardableResult
    public func insert(signedRecord envelope: SealedEnvelope, keepingMostRecent limit: Int) throws -> Bool {
        let record = try PeerRecord(signedEnvelope: envelope)
        return self.state.withLockedValue { state in
            Self.insert(record, envelope: envelope, for: self.id, into: &state, keepingMostRecent: limit)
        }
    }

    /// Trims the record set down to the `limit` most recent records (by sequence number).
    public func trimRecords(keepingMostRecent limit: Int) {
        self.state.withLockedValue { Self.trim(&$0, keepingMostRecent: limit) }
    }

    /// Removes all of the records (and their signed envelopes) associated with this peer.
    public func removeAllRecords() {
        self.state.withLockedValue {
            $0.records.removeAll()
            $0.envelopes.removeAll()
        }
    }

    private static func insert(
        _ record: PeerRecord,
        envelope: SealedEnvelope,
        for id: PeerID,
        into state: inout State,
        keepingMostRecent limit: Int?
    ) -> Bool {
        guard record.peerID == id else { return false }
        let seq = record.sequenceNumber
        if let existing = state.records.first(where: { $0.sequenceNumber == seq }) {
            /// Only attach the envelope to an unsigned copy of the same record.
            guard state.envelopes[seq] == nil, existing.equals(record) else { return false }
            state.envelopes[seq] = envelope
            return true
        }
        state.records.insert(record)
        state.envelopes[seq] = envelope
        if let limit { Self.trim(&state, keepingMostRecent: limit) }
        return state.records.contains(record)
    }

    /// Keeps the `limit` most recent records (by sequence number), and only the envelopes of the records kept.
    private static func trim(_ state: inout State, keepingMostRecent limit: Int) {
        guard limit >= 0 else { return }
        guard state.records.count > limit else { return }
        state.records = Set(
            state.records.sorted { $0.sequenceNumber > $1.sequenceNumber }.prefix(limit)
        )
        let kept = Set(state.records.map(\.sequenceNumber))
        state.envelopes = state.envelopes.filter { kept.contains($0.key) }
    }

    /// Returns a detached copy of this peer, taken under a single lock acquisition.
    ///
    /// Use this when handing a peer out across an API boundary so callers can't mutate the
    /// store's live state behind its back.
    public func copy() -> ComprehensivePeer {
        let state = self.state.withLockedValue { $0 }
        return ComprehensivePeer(id: self.id, state: state)
    }

    /// Wraps an existing state as is, without re-validating its envelopes.
    private init(id: PeerID, state: State) {
        self.id = id
        self.state = .init(state)
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
            🔏 Signed Records: \(state.envelopes.keys.sorted(by: >).map(String.init).joined(separator: ", "))
            \(String(repeating: "-", count: header.count + 2))
            """
    }
}
