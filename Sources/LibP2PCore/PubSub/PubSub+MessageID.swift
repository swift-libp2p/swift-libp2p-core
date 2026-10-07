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

public import Multihash

import struct Crypto.SHA256

/// - Warning: Message IDs are used to drop duplicates, so choose a cryptographic `HashFunction`.
///   - `.identity` makes each ID as large as the bytes it covers, bloating the seen-cache and IHAVE gossip.
///   - `.md5` and `.sha1` have practical collision attacks. A peer could craft a message that collides
///     with one it expects you to receive, so that the real one is dropped as a duplicate.
///
///   Every peer on a topic must also use the same function, or their IDs won't line up for IHAVE / IWANT.
extension PubSub.MessageIDFunction {

    /// Calculates a Message's ID as the hash of the Sequence Number followed by the Sender using the specified `HashFunction`
    ///
    /// - Warning: Avoid `.identity`, `.md5` and `.sha1`. See the extension's documentation.
    /// - Note: Every peer on a topic must also use the same function, or their IDs won't line up for IHAVE / IWANT.
    public static func hashSequenceNumberAndFromFields(using hf: HashFunction) -> PubSub.MessageIDFunction {
        .custom { message in sequenceNumberAndFromDigest(of: message, using: hf) }
    }

    /// Calculates a Message's ID as the hash of the Sequence Number, Sender, Data and Topic fields (in that order), using the specified `HashFunction`
    ///
    /// - Warning: Avoid `.identity`, `.md5` and `.sha1`. See the extension's documentation.
    /// - Note: Every peer on a topic must also use the same function, or their IDs won't line up for IHAVE / IWANT.
    public static func hashEverything(using hf: HashFunction) -> PubSub.MessageIDFunction {
        .custom { message in everythingDigest(of: message, using: hf) }
    }

    /// Calculates a Message's ID as the hash of its Data, using the specified `HashFunction`.
    ///
    /// The usual choice for `StrictNoSign` topics, where messages carry no sender or sequence number.
    ///
    /// - Warning: Avoid `.identity`, `.md5` and `.sha1`. See the extension's documentation.
    /// - Note: Every peer on a topic must also use the same function, or their IDs won't line up for IHAVE / IWANT.
    public static func contentHash(using hf: HashFunction) -> PubSub.MessageIDFunction {
        .custom { message in contentDigest(of: message, using: hf) }
    }

    /// Computes the ID for the `message`, exactly as a router using this function would.
    public func messageID(for message: PubSubMessage) -> [UInt8] {
        [UInt8](self.messageIDFunction(message))
    }

    // MARK: - Digests shared by the built-in cases and the `using:` variants

    static func sequenceNumberAndFromDigest(of message: PubSubMessage, using hf: HashFunction) -> Data {
        digest(of: [message.seqno, message.from], using: hf)
    }

    static func everythingDigest(of message: PubSubMessage, using hf: HashFunction) -> Data {
        digest(of: [message.seqno, message.from, message.data] + message.topicIds.map { Data($0.utf8) }, using: hf)
    }

    static func contentDigest(of message: PubSubMessage, using hf: HashFunction) -> Data {
        digest(of: [message.data], using: hf)
    }

    /// Hashes the concatenation of `parts`.
    static func digest(of parts: [Data], using hf: HashFunction) -> Data {
        /// If our hash is SHA2_256 use swift-crypto's implementation because it's faster
        if hf == .sha2_256 {
            var hasher = SHA256()
            for part in parts { hasher.update(data: part) }
            return Data(hasher.finalize())
        }
        /// Otherwise fall back on Multihash's implementations
        return Data(hf.hash(parts.joined()))
    }
}

extension PubSubMessage {
    /// Computes the ID for the `message` using the specified `MessageIDFunction` method
    public func messageID(using method: PubSub.MessageIDFunction) -> [UInt8] {
        method.messageID(for: self)
    }
}
