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

/// Represents a number of bytes.
///
/// Byte counts are created with one of the named factory methods, or with `init(value:)` for a
/// raw count
///
/// ```swift
/// let a: ByteCount = .bytes(1_000_000)    // 1000000
/// let b: ByteCount = .megabytes(1)        // 1000000
/// let c: ByteCount = .mebibytes(1)        // 1048576
/// ```
///
/// - Note:
///   `kilobytes(_:)` and friends are powers of 1,000,
///   while `kibibytes(_:)` and friends are powers of 1,024.
public struct ByteCount: Hashable, Sendable {
    /// The value in Bytes
    public let value: Int

    public init(value: Int) {
        self.value = value
    }
}

// MARK: - Named multiples

extension ByteCount {

    /// An amount of `count` bytes.
    public static func bytes(_ count: Int) -> ByteCount {
        ByteCount(value: count)
    }

    /// An amount of `count` kilobytes, where one kilobyte is 1,000 bytes.
    public static func kilobytes(_ count: Int) -> ByteCount {
        ByteCount(value: 1_000 * count)
    }

    /// An amount of `count` megabytes, where one megabyte is 1,000,000 bytes.
    public static func megabytes(_ count: Int) -> ByteCount {
        ByteCount(value: 1_000_000 * count)
    }

    /// An amount of `count` gigabytes, where one gigabyte is 1,000,000,000 bytes.
    public static func gigabytes(_ count: Int) -> ByteCount {
        ByteCount(value: 1_000_000_000 * count)
    }

    /// An amount of `count` kibibytes, where one kibibyte is 1,024 bytes.
    public static func kibibytes(_ count: Int) -> ByteCount {
        ByteCount(value: 1024 * count)
    }

    /// An amount of `count` mebibytes, where one mebibyte is 1,048,576 bytes.
    public static func mebibytes(_ count: Int) -> ByteCount {
        ByteCount(value: 1024 * 1024 * count)
    }

    /// An amount of `count` gibibytes, where one gibibyte is 1,073,741,824 bytes.
    public static func gibibytes(_ count: Int) -> ByteCount {
        ByteCount(value: 1024 * 1024 * 1024 * count)
    }

    /// No bytes at all.
    public static var zero: ByteCount { ByteCount(value: 0) }

    /// The largest count representable.
    public static var unlimited: ByteCount { ByteCount(value: .max) }
}

// MARK: - Comparable

extension ByteCount: Comparable {
    public static func < (lhs: ByteCount, rhs: ByteCount) -> Bool {
        lhs.value < rhs.value
    }
}
