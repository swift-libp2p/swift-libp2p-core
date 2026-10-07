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

import Foundation
import Multihash
import Testing

@testable import LibP2PCore

@Suite("MessageIDFunction Tests")
struct MessageIDFunctionTests {

    struct Message: PubSubMessage {
        var from = Data([0x01, 0x02])
        var data = Data("hello".utf8)
        var seqno = Data([0, 0, 0, 0, 0, 0, 0, 1])
        var topicIds = ["a", "b"]
        var signature = Data()
        var key = Data()
    }

    /// Expected values were computed independently (`shasum -a 256`), so these also pin the order
    /// of the hashed fields. They match swift-libp2p-pubsub's `MessageIDStrategy`.
    @Test func hashSequenceNumberAndFromFieldsIsSHA256OfSeqnoThenFrom() {
        let id = PubSub.MessageIDFunction.hashSequenceNumberAndFromFields.messageIDFunction(Message())
        #expect(hex(id) == "5e90e8fc309c2d85905322f16a37353e3658c13547423e2e18457d88f27b4022")
    }

    @Test func hashEverythingIsSHA256OfSeqnoFromDataAndTopics() {
        let id = PubSub.MessageIDFunction.hashEverything.messageIDFunction(Message())
        #expect(hex(id) == "4ba41fc4737854434c9ff818ce6c9607a4cc396b7c6914ac8b3912ec3cd4e833")
    }

    @Test func contentHashIsSHA256OfData() {
        let id = PubSub.MessageIDFunction.contentHash.messageIDFunction(Message())
        #expect(hex(id) == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
    }

    /// `contentHash` must stay a `.custom` function so it doesn't add a case to the enum.
    @Test func contentHashIsACustomFunction() {
        guard case .custom = PubSub.MessageIDFunction.contentHash else {
            Issue.record("expected .contentHash to be a .custom MessageIDFunction")
            return
        }
    }

    @Test func hashedIDsDependOnlyOnTheirFields() {
        var other = Message()
        other.signature = Data([0xFF])
        other.key = Data([0xEE])
        for function in [PubSub.MessageIDFunction.hashSequenceNumberAndFromFields, .hashEverything, .contentHash] {
            #expect(function.messageIDFunction(Message()) == function.messageIDFunction(other))
        }

        other.data = Data("goodbye".utf8)
        #expect(
            PubSub.MessageIDFunction.hashSequenceNumberAndFromFields.messageIDFunction(Message())
                == PubSub.MessageIDFunction.hashSequenceNumberAndFromFields.messageIDFunction(other)
        )
        #expect(
            PubSub.MessageIDFunction.hashEverything.messageIDFunction(Message())
                != PubSub.MessageIDFunction.hashEverything.messageIDFunction(other)
        )
    }

    // MARK: - Custom hash functions (PubSub+MessageID.swift)

    /// With SHA2-256 the `using:` variants must produce the same IDs as the built-in cases.
    @Test func sha256VariantsMatchTheBuiltInCases() {
        let message = Message()
        let pairs: [(PubSub.MessageIDFunction, PubSub.MessageIDFunction)] = [
            (.hashSequenceNumberAndFromFields, .hashSequenceNumberAndFromFields(using: .sha2_256)),
            (.hashEverything, .hashEverything(using: .sha2_256)),
            (.contentHash, .contentHash(using: .sha2_256)),
        ]
        for (builtIn, variant) in pairs {
            #expect(builtIn.messageIDFunction(message) == variant.messageIDFunction(message))
        }
    }

    /// SHA3-256 vectors computed independently (Python `hashlib.sha3_256`).
    @Test func sha3_256Variants() {
        let message = Message()
        #expect(
            hex(PubSub.MessageIDFunction.hashSequenceNumberAndFromFields(using: .sha3_256).messageIDFunction(message))
                == "5ee7b2614655402e3754d91630d816b33bc517510623d2deb579ef9cecebcf4b"
        )
        #expect(
            hex(PubSub.MessageIDFunction.hashEverything(using: .sha3_256).messageIDFunction(message))
                == "80ede417a9a815870e11173b396ce97e5dd88648d6808250a9b830583ffa27a9"
        )
        #expect(
            hex(PubSub.MessageIDFunction.contentHash(using: .sha3_256).messageIDFunction(message))
                == "3338be694f50c5f338814986cdf0686453a888b84f424d792af4b9202398f392"
        )
    }

    /// SHA2-512 vectors computed independently (`openssl dgst -sha512`).
    @Test func sha2_512Variants() {
        let message = Message()
        let everything = PubSub.MessageIDFunction.hashEverything(using: .sha2_512).messageIDFunction(message)
        #expect(everything.count == 64)
        #expect(
            hex(everything)
                == "39b8e5cadd2382a87d9436ddd8c09bd4b3839a9529b552ea501500305e98969c78daf2a9582f7a99aa119d0807730184b72d3a93a12cc03cba4c3be8e23bc30c"
        )
        #expect(
            hex(PubSub.MessageIDFunction.contentHash(using: .sha2_512).messageIDFunction(message))
                == "9b71d224bd62f3785d96d46ad3ea3d73319bfbc2890caadae2dff72519673ca72323c3d99ba5c11d7c7acc6e14b8c5da0c4663475c2e5c3adef46f73bcdec043"
        )
    }

    /// The `using:` variants are `.custom` functions, so they don't add cases to the enum.
    @Test func hashFunctionVariantsAreCustomFunctions() {
        let variants: [PubSub.MessageIDFunction] = [
            .hashSequenceNumberAndFromFields(using: .sha3_256),
            .hashEverything(using: .sha3_256),
            .contentHash(using: .sha3_256),
        ]
        for variant in variants {
            guard case .custom = variant else {
                Issue.record("expected a .custom MessageIDFunction, got \(variant)")
                continue
            }
        }
    }

    /// `messageID(for:)` (default hasher) and `messageIDFunction` must agree for every case.
    @Test func messageIDForMatchesMessageIDFunction() {
        let message = Message()
        let functions: [PubSub.MessageIDFunction] = [
            .hashSequenceNumberAndFromFields,
            .hashEverything,
            .concatFromAndSequenceFields,
            .contentHash,
            .hashEverything(using: .sha3_256),
            .custom { Data($0.data.reversed()) },
        ]
        for function in functions {
            #expect(function.messageID(for: message) == [UInt8](function.messageIDFunction(message)))
        }
    }

    @Test func concatFromAndSequenceFieldsMessageID() {
        #expect(
            PubSub.MessageIDFunction.concatFromAndSequenceFields.messageID(for: Message())
                == [0x01, 0x02, 0, 0, 0, 0, 0, 0, 0, 1]
        )
    }

    /// SHA2-256 is special-cased onto swift-crypto, every other function goes through Multihash.
    /// Both paths must produce the same digest, whether the input is split into parts or not.
    @Test func sha256FastPathMatchesMultihash() {
        let parts = [Data([0, 0, 0, 0, 0, 0, 0, 1]), Data(), Data([0x01, 0x02]), Data("hello".utf8)]
        let joined = parts.reduce(Data(), +)
        let fast = PubSub.MessageIDFunction.digest(of: parts, using: .sha2_256)
        #expect(fast == Data(HashFunction.sha2_256.hash(joined)))
        #expect(fast == PubSub.MessageIDFunction.digest(of: [joined], using: .sha2_256))
    }

    /// The non-fast path hashes the concatenation of the parts, same as hashing them pre-joined.
    @Test func multihashPathHashesTheConcatenation() {
        let parts = [Data("hel".utf8), Data("lo".utf8)]
        #expect(
            hex(PubSub.MessageIDFunction.digest(of: parts, using: .sha3_256))
                == "3338be694f50c5f338814986cdf0686453a888b84f424d792af4b9202398f392"
        )
    }

    @Test func pubSubMessageMessageIDUsesTheGivenFunction() {
        let message = Message()
        for function in [PubSub.MessageIDFunction.hashEverything, .contentHash(using: .sha2_512)] {
            #expect(message.messageID(using: function) == function.messageID(for: message))
        }
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
