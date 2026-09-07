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

import NIOCore
import Testing
import VarInt

@testable import LibP2PCore

@Suite("ByteBuffer VarInt")
struct ByteBufferVarintTests {

    private func buffer(_ bytes: [UInt8]) -> ByteBuffer {
        ByteBufferAllocator().buffer(bytes: bytes)
    }

    // MARK: - Round trips

    @Test func roundTripsUnsignedValues() throws {
        for value: UInt64 in [0, 1, 127, 128, 255, 300, 16383, 16384, 1 << 40, 1 << 63, .max] {
            var buf = ByteBufferAllocator().buffer(capacity: 16)
            let written = buf.writeVarInt(value)

            #expect(written == value.varIntSize, "wrote the wrong number of bytes for \(value)")
            #expect(buf.readableBytes == written)

            let decoded = try buf.readVarInt()
            #expect(decoded == value, "round-trip mismatch for \(value)")
            #expect(buf.readableBytes == 0, "did not consume the whole VarInt for \(value)")
        }
    }

    @Test func roundTripsSignedValuesUnderBothConventions() throws {
        for encoding in VarInt.SignedEncoding.allCases {
            for value: Int64 in [.min, -1_000_000, -1, 0, 1, 1_000_000, .max] {
                var buf = ByteBufferAllocator().buffer(capacity: 16)
                let written = buf.writeSignedVarInt(value, encoding)
                #expect(written == value.varIntSize(encoding))

                let decoded = try buf.readSignedVarInt(encoding)
                #expect(decoded == value, "round-trip mismatch for \(value) under \(encoding)")
                #expect(buf.readableBytes == 0)
            }
        }
    }

    @Test func roundTripsLengthPrefixedFrames() throws {
        let payloads: [[UInt8]] = [
            [],
            [0x01],
            Array(repeating: 0xAB, count: 127),
            Array(repeating: 0xCD, count: 300),
        ]

        var buf = ByteBufferAllocator().buffer(capacity: 1024)
        for payload in payloads {
            buf.writeVarIntLengthPrefixed(payload)
        }

        // A second frame written from a ByteBuffer rather than a collection, to
        // cover the other overload.
        buf.writeVarIntLengthPrefixed(buffer([0xEE, 0xFF]))

        for payload in payloads {
            let frame = try buf.readVarIntLengthPrefixedSlice()
            #expect(frame.map { Array($0.readableBytesView) } == payload)
        }

        let last = try buf.readVarIntLengthPrefixedSlice()
        #expect(last.map { Array($0.readableBytesView) } == [0xEE, 0xFF])
        #expect(buf.readableBytes == 0)
    }

    // MARK: - Partial reads

    /// An incomplete VarInt reports `nil` and consumes nothing, so the read
    /// is retriable byte by byte as the network delivers them.
    /// Useful for `ByteToMessageDecoder`s
    @Test func anIncompleteVarIntConsumesNothing() throws {
        let encoded = UInt64(1 << 45).varIntBytes.bytes

        for prefixLength in 0..<encoded.count {
            var buf = buffer(Array(encoded.prefix(prefixLength)))
            let result = try buf.readVarInt()
            #expect(result == nil, "decoded from only \(prefixLength) of \(encoded.count) bytes")
            #expect(buf.readableBytes == prefixLength, "a short read consumed bytes")
        }

        // Feed the encoding one byte at a time, the value appears exactly when the
        // last byte lands, and nothing is consumed before then.
        var incremental = ByteBufferAllocator().buffer(capacity: 16)
        for (offset, byte) in encoded.enumerated() {
            incremental.writeInteger(byte)
            let result = try incremental.readVarInt()
            if offset < encoded.count - 1 {
                #expect(result == nil)
                #expect(incremental.readableBytes == offset + 1)
            } else {
                #expect(result == 1 << 45)
                #expect(incremental.readableBytes == 0)
            }
        }
    }

    @Test func anIncompleteLengthPrefixedFrameConsumesNothing() throws {
        let frame = Array(repeating: UInt8(0x7E), count: 200).uVarIntLengthPrefixed

        for prefixLength in 0..<frame.count {
            var buf = buffer(Array(frame.prefix(prefixLength)))
            let result = try buf.readVarIntLengthPrefixedSlice()
            #expect(result == nil, "decoded a frame from only \(prefixLength) of \(frame.count) bytes")
            #expect(buf.readableBytes == prefixLength, "a short frame read consumed bytes")
        }

        var complete = buffer(frame)
        let body = try complete.readVarIntLengthPrefixedSlice()
        #expect(body?.readableBytes == 200)
        #expect(complete.readableBytes == 0)
    }

    // MARK: - Malformed input

    @Test func malformedVarIntsThrowAndRestoreTheReaderIndex() throws {
        // Non-minimal, rejected by default.
        var nonMinimal = buffer([0x81, 0x00])
        #expect(throws: VarIntError.notMinimal) { try nonMinimal.readVarInt() }
        #expect(nonMinimal.readableBytes == 2, "a throwing read consumed bytes")

        // …and accepted when the caller opts out.
        let relaxed = try nonMinimal.readVarInt(requireMinimal: false)
        #expect(relaxed == 1)

        // Overflow, eleven bytes cannot fit in 64 bits.
        var overflowing = buffer(Array(repeating: 0xFF, count: 12))
        #expect(throws: VarIntError.overflow) { try overflowing.readVarInt() }
        #expect(overflowing.readableBytes == 12)
    }

    /// The limit is what lets a framing decoder reject an oversized announcement
    /// without first computing a bounded read window.
    @Test func aLimitIsEnforcedBeforeTheBodyIsBuffered() throws {
        let limit: UInt64 = 1 << 20

        // The max value is accepted.
        var atLimit = ByteBufferAllocator().buffer(capacity: 16)
        atLimit.writeVarInt(limit)
        #expect(try atLimit.readVarInt(limit: limit) == limit)

        // One over the limit is rejected, with nothing consumed.
        var overLimit = ByteBufferAllocator().buffer(capacity: 16)
        overLimit.writeVarInt(limit + 1)
        let announcedBytes = overLimit.readableBytes
        #expect(throws: VarIntError.exceedsLimit(limit: limit)) { try overLimit.readVarInt(limit: limit) }
        #expect(overLimit.readableBytes == announcedBytes)

        // A run of continuation bytes is rejected after 3 bytes rather than 10
        var hostile = buffer(Array(repeating: 0xFF, count: 3))
        #expect(throws: VarIntError.exceedsLimit(limit: limit)) { try hostile.readVarInt(limit: limit) }

        // The same ceiling applied to a whole frame.
        var oversizedFrame = ByteBufferAllocator().buffer(capacity: 16)
        oversizedFrame.writeVarInt(limit + 1)
        #expect(throws: VarIntError.exceedsLimit(limit: limit)) {
            try oversizedFrame.readVarIntLengthPrefixedSlice(limit: limit)
        }
    }

    // MARK: - Limits expressed as byte counts

    /// The `ByteCount` overloads of the `UInt64` ones, so the same ceiling has to
    /// behave identically between them.
    @Test func aByteCountLimitMatchesTheEquivalentUInt64Limit() throws {
        let ceiling: ByteCount = .mebibytes(1)
        #expect(ceiling.value == 1 << 20)

        // At the ceiling, accepted.
        var atLimit = ByteBufferAllocator().buffer(capacity: 16)
        atLimit.writeVarInt(UInt64(ceiling.value))
        #expect(try atLimit.readVarInt(limit: ceiling) == UInt64(ceiling.value))

        // One over, rejected with nothing consumed, and reporting the same limit the
        // `UInt64` spelling would.
        var overLimit = ByteBufferAllocator().buffer(capacity: 16)
        overLimit.writeVarInt(UInt64(ceiling.value) + 1)
        let announcedBytes = overLimit.readableBytes
        #expect(throws: VarIntError.exceedsLimit(limit: 1 << 20)) { try overLimit.readVarInt(limit: ceiling) }
        #expect(overLimit.readableBytes == announcedBytes)

        // The whole-frame and peeking entry points take the same ceiling.
        var frame = ByteBufferAllocator().buffer(capacity: 32)
        frame.writeVarIntLengthPrefixed(Array(repeating: UInt8(0xAB), count: 300))
        var oversized = frame
        #expect(throws: VarIntError.exceedsLimit(limit: 299)) {
            try oversized.readVarIntLengthPrefixedSlice(limit: .bytes(299))
        }
        #expect(try frame.readVarIntLengthPrefixedSlice(limit: .kibibytes(1))?.readableBytes == 300)
        #expect(try frame.getVarInt(at: frame.readerIndex, limit: .kibibytes(1)) == nil)
    }

    /// `ByteCount` is signed, the wire limit is not. A negative ceiling has to clamp.
    @Test func aNegativeByteCountLimitClampsToZero() throws {
        var buf = ByteBufferAllocator().buffer(capacity: 16)
        buf.writeVarInt(1)
        #expect(throws: VarIntError.exceedsLimit(limit: 0)) { try buf.readVarInt(limit: ByteCount(value: -5)) }
        #expect(buf.readableBytes == 1, "a throwing read consumed bytes")
    }

    @Test func aLiteralLimitIsStillUnambiguous() throws {
        var buf = ByteBufferAllocator().buffer(capacity: 16)
        buf.writeVarInt(4096)
        #expect(try buf.readVarInt(limit: 4096) == 4096)

        var frame = ByteBufferAllocator().buffer(capacity: 32)
        frame.writeVarIntLengthPrefixed(Array(repeating: UInt8(0x01), count: 8))
        #expect(try frame.readVarIntLengthPrefixedSlice(limit: 4096)?.readableBytes == 8)
    }

    // MARK: - Peeking

    @Test func getVarIntDoesNotMoveTheReaderIndex() throws {
        var buf = ByteBufferAllocator().buffer(capacity: 32)
        buf.writeBytes([0xAA, 0xBB])
        buf.writeVarInt(16384)
        buf.writeBytes([0xCC])

        let readableBefore = buf.readableBytes
        let peeked = try buf.getVarInt(at: buf.readerIndex + 2)
        #expect(peeked?.value == 16384)
        #expect(peeked?.byteCount == 3)
        #expect(buf.readableBytes == readableBefore, "getVarInt consumed bytes")

        // Reports nil rather than throwing when the VarInt is incomplete.
        let truncated = buffer([0x81, 0x81])
        #expect(try truncated.getVarInt(at: truncated.readerIndex) == nil)
        #expect(try truncated.getVarInt(at: truncated.writerIndex) == nil)
    }

    // MARK: - Interop with the collection API

    /// The same bytes have to decode identically whether they are read through
    /// `ByteBuffer` or through the package's collection entry points.
    @Test func agreesWithTheCollectionAPI() throws {
        for value: UInt64 in [0, 1, 127, 128, 300, 16384, 1 << 56, .max] {
            var buf = ByteBufferAllocator().buffer(capacity: 16)
            buf.writeVarInt(value)

            let wireBytes = Array(buf.readableBytesView)
            #expect(wireBytes == value.varIntBytes.bytes)

            let viaCollection = try VarInt.decode(wireBytes)
            let viaBuffer = try buf.readVarInt()
            #expect(viaBuffer == viaCollection.value)
            #expect(viaCollection.end == wireBytes.count)
        }
    }

    /// A frame built with `uVarIntLengthPrefixed`, the form used for PeerRecord
    /// signing payloads and the plaintext handshake, reads back through the
    /// ByteBuffer API, and vice versa.
    @Test func lengthPrefixedFramingIsInteroperable() throws {
        let payload = Array("hello libp2p".utf8)

        // Written by the package, read by NIO.
        var fromPackage = buffer(payload.uVarIntLengthPrefixed)
        let readByNIO = try fromPackage.readVarIntLengthPrefixedSlice()
        #expect(readByNIO.map { Array($0.readableBytesView) } == payload)

        // Written by NIO, read by the package.
        var fromNIO = ByteBufferAllocator().buffer(capacity: 32)
        fromNIO.writeVarIntLengthPrefixed(payload)
        #expect(Array(fromNIO.readableBytesView) == payload.uVarIntLengthPrefixed)

        var reader = VarIntReader(Array(fromNIO.readableBytesView))
        let readByPackage = Array(try reader.readUVarIntLengthPrefixed())
        let isEmpty = reader.isEmpty
        #expect(readByPackage == payload)
        #expect(isEmpty)
    }
}
