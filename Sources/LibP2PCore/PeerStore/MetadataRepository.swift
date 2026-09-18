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

public typealias Metadata = [String: [UInt8]]

public struct MetadataBook: Sendable {
    public enum Keys: String, Sendable {
        case agentVersion
        case protocolVersion
        case latency
        case lastHandshake
        case observedAddress
        case prunable
        case discovered
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
        /// How willing we are to evict a peer when the peerstore needs to make room.
        public enum Prunable: UInt8, Codable, Sendable, CustomStringConvertible {
            /// Evict freely. This is the default for any peer with no explicit prunability.
            case prunable = 0
            /// Evict only once every `prunable` peer has been exhausted.
            case preferred
            /// Never evict.
            case necessary

            public var description: String {
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
            "Peer Importance: \(prunable.description)"
        }
    }
}

// Deprecated UpperCamelCase spellings of the `MetadataBook.Keys` cases (pre-0.6.0).
extension MetadataBook.Keys {
    @available(*, deprecated, renamed: "agentVersion")
    public static var AgentVersion: Self { .agentVersion }
    @available(*, deprecated, renamed: "protocolVersion")
    public static var ProtocolVersion: Self { .protocolVersion }
    @available(*, deprecated, renamed: "latency")
    public static var Latency: Self { .latency }
    @available(*, deprecated, renamed: "lastHandshake")
    public static var LastHandshake: Self { .lastHandshake }
    @available(*, deprecated, renamed: "observedAddress")
    public static var ObservedAddress: Self { .observedAddress }
    @available(*, deprecated, renamed: "prunable")
    public static var Prunable: Self { .prunable }
    @available(*, deprecated, renamed: "discovered")
    public static var Discovered: Self { .discovered }
}

public protocol MetadataRepository {
    func removeAllMetadata(forPeer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func add(metaKey: String, data: [UInt8], toPeer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func add(metaKey: MetadataBook.Keys, data: [UInt8], toPeer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func remove(metaKey: String, fromPeer: PeerID, on: EventLoop?) -> EventLoopFuture<Void>
    func getMetadata(forPeer: PeerID, on: EventLoop?) -> EventLoopFuture<Metadata>
    //func getMetadata(metaKey:String, forPeer:PeerID, on:EventLoop?) -> EventLoopFuture<(key:String, value: [UInt8])>
    //func getMetadata(metaKey:MetadataBook.Keys, forPeer:PeerID, on:EventLoop?) -> EventLoopFuture<(key:String, value: [UInt8])>
}

extension MetadataRepository {
    public func removeAllMetadata(forPeer: PeerID) -> EventLoopFuture<Void> {
        removeAllMetadata(forPeer: forPeer, on: nil)
    }
    public func add(metaKey: String, data: [UInt8], toPeer: PeerID) -> EventLoopFuture<Void> {
        add(metaKey: metaKey, data: data, toPeer: toPeer, on: nil)
    }
    /// Default implementation of the typed-key requirement, forwarding to the raw-key variant.
    public func add(
        metaKey: MetadataBook.Keys,
        data: [UInt8],
        toPeer: PeerID,
        on: EventLoop?
    ) -> EventLoopFuture<Void> {
        add(metaKey: metaKey.rawValue, data: data, toPeer: toPeer, on: on)
    }
    public func add(metaKey: MetadataBook.Keys, data: [UInt8], toPeer: PeerID) -> EventLoopFuture<Void> {
        add(metaKey: metaKey.rawValue, data: data, toPeer: toPeer, on: nil)
    }
    public func remove(metaKey: String, fromPeer: PeerID) -> EventLoopFuture<Void> {
        remove(metaKey: metaKey, fromPeer: fromPeer, on: nil)
    }
    public func remove(metaKey: MetadataBook.Keys, fromPeer: PeerID, on: EventLoop?) -> EventLoopFuture<Void> {
        remove(metaKey: metaKey.rawValue, fromPeer: fromPeer, on: on)
    }
    public func remove(metaKey: MetadataBook.Keys, fromPeer: PeerID) -> EventLoopFuture<Void> {
        remove(metaKey: metaKey.rawValue, fromPeer: fromPeer, on: nil)
    }
    public func getMetadata(forPeer: PeerID) -> EventLoopFuture<Metadata> {
        getMetadata(forPeer: forPeer, on: nil)
    }
}

// MARK: - Typed Metadata

/// Typed accessors layered over the raw `[String: [UInt8]]` metadata book.
///
/// The standard metadata types are encoded using the following rules:
/// - `Codable` values (``MetadataBook/LatencyMetadata``, ``MetadataBook/PrunableMetadata``) are
///   JSON.
/// - Timestamps (`lastHandshake`, `discovered`) are the UTF-8 decimal rendering of a
///   `timeIntervalSince1970`.
/// - Strings (`agentVersion`, `protocolVersion`, `observedAddress`) are raw UTF-8.
extension MetadataRepository {

    // MARK: Generic Codable access

    /// Stores `value` as JSON under `metaKey`.
    ///
    /// - Note: `on` is non-optional here because an encoding failure needs an `EventLoop` to fail
    ///   on. Use the `async` overload when you don't have one to hand.
    public func add(
        metaKey: String,
        value: some Encodable & Sendable,
        toPeer peer: PeerID,
        on: EventLoop
    ) -> EventLoopFuture<Void> {
        do {
            let encoded = try Array(JSONEncoder().encode(value))
            return self.add(metaKey: metaKey, data: encoded, toPeer: peer, on: on)
        } catch {
            return on.makeFailedFuture(error)
        }
    }

    public func add(
        metaKey: MetadataBook.Keys,
        value: some Encodable & Sendable,
        toPeer peer: PeerID,
        on: EventLoop
    ) -> EventLoopFuture<Void> {
        self.add(metaKey: metaKey.rawValue, value: value, toPeer: peer, on: on)
    }

    /// Decodes the JSON value stored under `metaKey`, or `nil` when absent or undecodable.
    public func getMetadata<T: Decodable & Sendable>(
        _ type: T.Type,
        forKey metaKey: String,
        forPeer peer: PeerID,
        on: EventLoop? = nil
    ) -> EventLoopFuture<T?> {
        self.getMetadata(forPeer: peer, on: on).map { metadata in
            guard let raw = metadata[metaKey] else { return nil }
            return try? JSONDecoder().decode(T.self, from: Data(raw))
        }
    }

    public func getMetadata<T: Decodable & Sendable>(
        _ type: T.Type,
        forKey metaKey: MetadataBook.Keys,
        forPeer peer: PeerID,
        on: EventLoop? = nil
    ) -> EventLoopFuture<T?> {
        self.getMetadata(type, forKey: metaKey.rawValue, forPeer: peer, on: on)
    }

    // MARK: Timestamps

    /// Encodes a `Date` the way the metadata book has always stored timestamps: the UTF-8
    /// decimal rendering of its `timeIntervalSince1970`.
    public static func encodeTimestamp(_ date: Date) -> [UInt8] {
        Array("\(date.timeIntervalSince1970)".utf8)
    }

    /// The inverse of ``encodeTimestamp(_:)``.
    public static func decodeTimestamp(_ bytes: [UInt8]) -> Date? {
        guard let interval = Double(String(decoding: bytes, as: UTF8.self)) else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

    public func setLastHandshake(
        _ date: Date,
        forPeer peer: PeerID,
        on: EventLoop? = nil
    ) -> EventLoopFuture<Void> {
        self.add(metaKey: .lastHandshake, data: Self.encodeTimestamp(date), toPeer: peer, on: on)
    }

    public func getLastHandshake(forPeer peer: PeerID, on: EventLoop? = nil) -> EventLoopFuture<Date?> {
        self.getMetadata(forPeer: peer, on: on).map { metadata in
            metadata[MetadataBook.Keys.lastHandshake.rawValue].flatMap(Self.decodeTimestamp)
        }
    }

    public func setDiscovered(
        _ date: Date,
        forPeer peer: PeerID,
        on: EventLoop? = nil
    ) -> EventLoopFuture<Void> {
        self.add(metaKey: .discovered, data: Self.encodeTimestamp(date), toPeer: peer, on: on)
    }

    public func getDiscovered(forPeer peer: PeerID, on: EventLoop? = nil) -> EventLoopFuture<Date?> {
        self.getMetadata(forPeer: peer, on: on).map { metadata in
            metadata[MetadataBook.Keys.discovered.rawValue].flatMap(Self.decodeTimestamp)
        }
    }

    // MARK: Prunability

    /// Marks how willing the peerstore should be to evict this peer under memory pressure.
    ///
    /// - Note: Peers with no explicit prunability are treated as ``MetadataBook/PrunableMetadata/Prunable/prunable``.
    public func setPrunability(
        _ prunable: MetadataBook.PrunableMetadata.Prunable,
        forPeer peer: PeerID,
        on: EventLoop
    ) -> EventLoopFuture<Void> {
        self.add(
            metaKey: .prunable,
            value: MetadataBook.PrunableMetadata(prunable: prunable),
            toPeer: peer,
            on: on
        )
    }

    public func getPrunability(
        forPeer peer: PeerID,
        on: EventLoop? = nil
    ) -> EventLoopFuture<MetadataBook.PrunableMetadata.Prunable> {
        self.getMetadata(MetadataBook.PrunableMetadata.self, forKey: .prunable, forPeer: peer, on: on)
            .map { $0?.prunable ?? .prunable }
    }

    // MARK: Latency

    public func setLatency(
        _ latency: MetadataBook.LatencyMetadata,
        forPeer peer: PeerID,
        on: EventLoop
    ) -> EventLoopFuture<Void> {
        self.add(metaKey: .latency, value: latency, toPeer: peer, on: on)
    }

    public func getLatency(
        forPeer peer: PeerID,
        on: EventLoop? = nil
    ) -> EventLoopFuture<MetadataBook.LatencyMetadata?> {
        self.getMetadata(MetadataBook.LatencyMetadata.self, forKey: .latency, forPeer: peer, on: on)
    }

    // MARK: Plain-string entries

    public func getStringMetadata(
        forKey metaKey: MetadataBook.Keys,
        forPeer peer: PeerID,
        on: EventLoop? = nil
    ) -> EventLoopFuture<String?> {
        self.getMetadata(forPeer: peer, on: on).map { metadata in
            metadata[metaKey.rawValue].map { String(decoding: $0, as: UTF8.self) }
        }
    }

    public func setStringMetadata(
        forKey metaKey: MetadataBook.Keys,
        value: String,
        forPeer peer: PeerID,
        on: EventLoop? = nil
    ) -> EventLoopFuture<Void> {
        self.add(metaKey: metaKey, data: Array(value.utf8), toPeer: peer, on: on)
    }

    public func getAgentVersion(forPeer peer: PeerID, on: EventLoop? = nil) -> EventLoopFuture<String?> {
        self.getStringMetadata(forKey: .agentVersion, forPeer: peer, on: on)
    }

    public func setAgentVersion(_ version: String, forPeer peer: PeerID, on: EventLoop? = nil) -> EventLoopFuture<Void>
    {
        self.setStringMetadata(forKey: .agentVersion, value: version, forPeer: peer, on: on)
    }

    public func getProtocolVersion(forPeer peer: PeerID, on: EventLoop? = nil) -> EventLoopFuture<String?> {
        self.getStringMetadata(forKey: .protocolVersion, forPeer: peer, on: on)
    }

    public func setProtocolVersion(
        _ version: String,
        forPeer peer: PeerID,
        on: EventLoop? = nil
    ) -> EventLoopFuture<Void> {
        self.setStringMetadata(forKey: .protocolVersion, value: version, forPeer: peer, on: on)
    }

    public func getObservedAddress(forPeer peer: PeerID, on: EventLoop? = nil) -> EventLoopFuture<Multiaddr?> {
        self.getStringMetadata(forKey: .observedAddress, forPeer: peer, on: on).map { string in
            string.flatMap { try? Multiaddr($0) }
        }
    }

    public func setObservedAddress(
        _ address: Multiaddr,
        forPeer peer: PeerID,
        on: EventLoop? = nil
    ) -> EventLoopFuture<Void> {
        self.setStringMetadata(forKey: .observedAddress, value: address.description, forPeer: peer, on: on)
    }
}

// MARK: - Async

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

    public func remove(metaKey: MetadataBook.Keys, fromPeer: PeerID) async throws {
        try await self.remove(metaKey: metaKey.rawValue, fromPeer: fromPeer, on: nil).get()
    }

    public func getMetadata(forPeer: PeerID) async throws -> Metadata {
        try await self.getMetadata(forPeer: forPeer, on: nil).get()
    }

    // MARK: Typed

    public func add(metaKey: String, value: some Encodable & Sendable, toPeer peer: PeerID) async throws {
        let encoded = try Array(JSONEncoder().encode(value))
        try await self.add(metaKey: metaKey, data: encoded, toPeer: peer, on: nil).get()
    }

    public func add(metaKey: MetadataBook.Keys, value: some Encodable & Sendable, toPeer peer: PeerID) async throws {
        try await self.add(metaKey: metaKey.rawValue, value: value, toPeer: peer)
    }

    public func getMetadata<T: Decodable & Sendable>(
        _ type: T.Type,
        forKey metaKey: MetadataBook.Keys,
        forPeer peer: PeerID
    ) async throws -> T? {
        try await self.getMetadata(type, forKey: metaKey, forPeer: peer, on: nil).get()
    }

    public func setLastHandshake(_ date: Date, forPeer peer: PeerID) async throws {
        try await self.setLastHandshake(date, forPeer: peer, on: nil).get()
    }

    public func getLastHandshake(forPeer peer: PeerID) async throws -> Date? {
        try await self.getLastHandshake(forPeer: peer, on: nil).get()
    }

    public func setDiscovered(_ date: Date, forPeer peer: PeerID) async throws {
        try await self.setDiscovered(date, forPeer: peer, on: nil).get()
    }

    public func getDiscovered(forPeer peer: PeerID) async throws -> Date? {
        try await self.getDiscovered(forPeer: peer, on: nil).get()
    }

    public func setPrunability(
        _ prunable: MetadataBook.PrunableMetadata.Prunable,
        forPeer peer: PeerID
    ) async throws {
        try await self.add(metaKey: .prunable, value: MetadataBook.PrunableMetadata(prunable: prunable), toPeer: peer)
    }

    public func getPrunability(forPeer peer: PeerID) async throws -> MetadataBook.PrunableMetadata.Prunable {
        try await self.getPrunability(forPeer: peer, on: nil).get()
    }

    public func setLatency(_ latency: MetadataBook.LatencyMetadata, forPeer peer: PeerID) async throws {
        try await self.add(metaKey: .latency, value: latency, toPeer: peer)
    }

    public func getLatency(forPeer peer: PeerID) async throws -> MetadataBook.LatencyMetadata? {
        try await self.getLatency(forPeer: peer, on: nil).get()
    }

    public func setAgentVersion(_ version: String, forPeer peer: PeerID) async throws {
        try await self.setAgentVersion(version, forPeer: peer, on: nil).get()
    }

    public func getAgentVersion(forPeer peer: PeerID) async throws -> String? {
        try await self.getAgentVersion(forPeer: peer, on: nil).get()
    }

    public func setProtocolVersion(_ version: String, forPeer peer: PeerID) async throws {
        try await self.setProtocolVersion(version, forPeer: peer, on: nil).get()
    }

    public func getProtocolVersion(forPeer peer: PeerID) async throws -> String? {
        try await self.getProtocolVersion(forPeer: peer, on: nil).get()
    }

    public func setObservedAddress(_ address: Multiaddr, forPeer peer: PeerID) async throws {
        try await self.setObservedAddress(address, forPeer: peer, on: nil).get()
    }

    public func getObservedAddress(forPeer peer: PeerID) async throws -> Multiaddr? {
        try await self.getObservedAddress(forPeer: peer, on: nil).get()
    }
}
