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

import Testing

@testable import LibP2PCore

@Suite("ByteCount")
struct ByteCountTests {

    @Test func decimalMultiplesArePowersOfTen() {
        #expect(ByteCount.bytes(512).value == 512)
        #expect(ByteCount.kilobytes(1).value == 1_000)
        #expect(ByteCount.megabytes(1).value == 1_000_000)
        #expect(ByteCount.gigabytes(1).value == 1_000_000_000)
        #expect(ByteCount.megabytes(4).value == 4_000_000)
    }

    @Test func binaryMultiplesArePowersOfTwo() {
        #expect(ByteCount.kibibytes(1).value == 1024)
        #expect(ByteCount.mebibytes(1).value == 1 << 20)
        #expect(ByteCount.gibibytes(1).value == 1 << 30)
        #expect(ByteCount.mebibytes(4).value == 4 << 20)
    }

    @Test func decimalAndBinaryMultiplesDiffer() {
        #expect(ByteCount.kilobytes(1) != ByteCount.kibibytes(1))
        #expect(ByteCount.kilobytes(1) < ByteCount.kibibytes(1))
        #expect(ByteCount.megabytes(1) != ByteCount.mebibytes(1))
        #expect(ByteCount.megabytes(1) < ByteCount.mebibytes(1))
        #expect(ByteCount.gigabytes(1) != ByteCount.gibibytes(1))
        #expect(ByteCount.gigabytes(1) < ByteCount.gibibytes(1))
    }

    @Test func rawCountsRoundTripThroughBothSpellings() {
        #expect(ByteCount(value: 1_000_000) == .megabytes(1))
        #expect(ByteCount(value: 1_000_000) == .bytes(1_000_000))
    }

    @Test func comparableAndBoundaryValues() {
        #expect(ByteCount.zero.value == 0)
        #expect(ByteCount.unlimited.value == Int.max)
        #expect(ByteCount.zero < .bytes(1))
        #expect(ByteCount.unlimited > .gibibytes(1))
        #expect([ByteCount.mebibytes(1), .zero, .kibibytes(1)].max() == .mebibytes(1))
    }
}
