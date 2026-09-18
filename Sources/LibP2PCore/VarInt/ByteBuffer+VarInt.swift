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

public import NIOCore
public import VarInt

extension ByteBuffer {

    // MARK: - Reading

    /// Reads an unsigned VarInt from the reader index.
    ///
    /// Useful when implementing a `ByteToMessageDecoder`, an incomplete VarInt
    /// consumes nothing and reports `nil`, so the same read can be retried when
    /// more bytes arrive.
    ///
    /// ```swift
    /// guard let length = try buffer.readVarInt(limit: maxMessageLength) else {
    ///     return .needMoreData
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - limit: The largest value to accept. `VarIntError.exceedsLimit` is
    ///     thrown as soon as the accumulated bits provably exceed it.
    ///   - requireMinimal: Whether to reject non-minimal encodings. Defaults to
    ///     `true`, matching the multiformats VarInt spec.
    /// - Returns: The decoded value, or `nil` if the buffer does not yet hold a
    ///   complete VarInt.
    /// - Throws: A `VarIntError` if the bytes cannot form a valid VarInt no
    ///   matter how many more arrive. The reader index is restored on a throw.
    public mutating func readVarInt(
        limit: UInt64 = .max,
        requireMinimal: Bool = true
    ) throws(VarIntError) -> UInt64? {
        let start = self.readerIndex
        var decoder = VarIntDecoder(limit: limit, requireMinimal: requireMinimal)

        while let byte: UInt8 = self.readInteger() {
            do {
                if let value = try decoder.push(byte) { return value }
            } catch {
                self.moveReaderIndex(to: start)
                throw error
            }
        }

        // Ran out of readable bytes part way through. Consume nothing.
        self.moveReaderIndex(to: start)
        return nil
    }

    /// Reads a signed VarInt from the reader index.
    ///
    /// - Parameters:
    ///   - encoding: How the signed value was mapped onto the encoded unsigned
    ///     value. Must match whatever the writer used.
    ///   - requireMinimal: Whether to reject non-minimal encodings or not.
    /// - Returns: The decoded value, or `nil` if the buffer does not yet hold a
    ///   complete VarInt.
    /// - Throws: A `VarIntError` if the bytes cannot form a valid VarInt no
    ///   matter how many more arrive. The reader index is restored on a throw.
    public mutating func readSignedVarInt(
        _ encoding: VarInt.SignedEncoding = .zigZag,
        requireMinimal: Bool = true
    ) throws(VarIntError) -> Int64? {
        guard let bits = try self.readVarInt(requireMinimal: requireMinimal) else { return nil }
        return encoding.signedValue(from: bits)
    }

    /// Reads a VarInt length prefix followed by that many bytes.
    ///
    /// Either half being incomplete reports `nil` and consumes nothing, so the
    /// whole frame read is retriable.
    ///
    /// - Parameters:
    ///   - limit: The largest body length to accept. An oversized announcement is
    ///     rejected while the prefix is being decoded.
    ///   - requireMinimal: Whether to reject a non-minimally encoded prefix or not.
    /// - Returns: The body as a slice, or `nil` if the complete frame isn't
    ///   available yet.
    /// - Throws: A `VarIntError` if the prefix is malformed or over `limit`, or
    ///   `.overflow` if the announced length can't be represented as an `Int`.
    public mutating func readVarIntLengthPrefixedSlice(
        limit: UInt64 = .max,
        requireMinimal: Bool = true
    ) throws(VarIntError) -> ByteBuffer? {
        let start = self.readerIndex

        guard let length = try self.readVarInt(limit: limit, requireMinimal: requireMinimal) else {
            return nil
        }

        guard let bodyLength = Int(exactly: length) else {
            self.moveReaderIndex(to: start)
            throw VarIntError.overflow
        }

        guard let body = self.readSlice(length: bodyLength) else {
            // The prefix arrived but the body hasn't. Put the prefix back.
            self.moveReaderIndex(to: start)
            return nil
        }

        return body
    }

    /// Decodes the unsigned VarInt at an absolute index without moving the reader.
    ///
    /// - Parameters:
    ///   - index: The absolute index to decode from.
    ///   - limit: The largest value to accept.
    ///   - requireMinimal: Whether to reject non-minimal encodings or not.
    /// - Returns: The decoded value and how many bytes it occupies, or `nil` if
    ///   the buffer does not hold a complete VarInt at `index`.
    public func getVarInt(
        at index: Int,
        limit: UInt64 = .max,
        requireMinimal: Bool = true
    ) throws(VarIntError) -> (value: UInt64, byteCount: Int)? {
        var decoder = VarIntDecoder(limit: limit, requireMinimal: requireMinimal)
        var offset = 0

        while let byte: UInt8 = self.getInteger(at: index + offset) {
            offset += 1
            if let value = try decoder.push(byte) { return (value, offset) }
        }

        return nil
    }

    // MARK: - Writing

    /// Writes `value` as an unsigned VarInt.
    ///
    /// - Returns: The number of bytes written, `1...10`.
    @discardableResult
    public mutating func writeVarInt(_ value: UInt64) -> Int {
        self.writeBytes(value.varIntBytes)
    }

    /// Writes `value` as a signed VarInt under `encoding`.
    ///
    /// - Returns: The number of bytes written.
    @discardableResult
    public mutating func writeSignedVarInt(
        _ value: Int64,
        _ encoding: VarInt.SignedEncoding = .zigZag
    ) -> Int {
        self.writeBytes(value.varIntBytes(encoding))
    }

    /// Writes an unsigned VarInt length prefix followed by `bytes`.
    ///
    /// - Returns: The total number of bytes written, prefix included.
    @discardableResult
    public mutating func writeVarIntLengthPrefixed(_ bytes: some Collection<UInt8>) -> Int {
        self.writeVarInt(UInt64(bytes.count)) + self.writeBytes(bytes)
    }

    /// Writes an unsigned VarInt length prefix followed by the readable bytes of `buffer`.
    ///
    /// - Note: `buffer` is not consumed.
    ///
    /// - Returns: The total number of bytes written, prefix included.
    @discardableResult
    public mutating func writeVarIntLengthPrefixed(_ buffer: ByteBuffer) -> Int {
        self.writeVarInt(UInt64(buffer.readableBytes)) + self.writeBytes(buffer.readableBytesView)
    }
}

// MARK: - ByteCount Overloads

extension ByteBuffer {

    /// Reads an unsigned VarInt from the reader index, rejecting values over `limit`.
    ///
    /// See `readVarInt(limit:requireMinimal:)`.
    ///
    /// - Parameters:
    ///   - limit: The largest value to accept as a ByteCount.
    ///     `VarIntError.exceedsLimit` is thrown as soon as the accumulated bits
    ///     provably exceed it.
    ///   - requireMinimal: Whether to reject non-minimal encodings. Defaults to
    ///     `true`, matching the multiformats VarInt spec.
    /// - Returns: The decoded value, or `nil` if the buffer does not yet hold a
    ///   complete VarInt.
    /// - Throws: A `VarIntError` if the bytes cannot form a valid VarInt no
    ///   matter how many more arrive. The reader index is restored on a throw.
    public mutating func readVarInt(
        limit: ByteCount,
        requireMinimal: Bool = true
    ) throws(VarIntError) -> UInt64? {
        try self.readVarInt(limit: UInt64(clamping: limit.value), requireMinimal: requireMinimal)
    }

    /// Reads a VarInt length prefix followed by that many bytes, rejecting bodies over `limit`.
    ///
    /// See `readVarIntLengthPrefixedSlice(limit:requireMinimal:)`.
    ///
    /// - Parameters:
    ///   - limit: The largest body length to accept as a ByteCount. An oversized
    ///     announcement is rejected while the prefix is being decoded.
    ///   - requireMinimal: Whether to reject a non-minimally encoded prefix or not.
    /// - Returns: The body as a slice, or `nil` if the complete frame isn't
    ///   available yet.
    /// - Throws: A `VarIntError` if the prefix is malformed or over `limit`, or
    ///   `.overflow` if the announced length can't be represented as an `Int`.
    public mutating func readVarIntLengthPrefixedSlice(
        limit: ByteCount,
        requireMinimal: Bool = true
    ) throws(VarIntError) -> ByteBuffer? {
        try self.readVarIntLengthPrefixedSlice(
            limit: UInt64(clamping: limit.value),
            requireMinimal: requireMinimal
        )
    }

    /// Decodes the unsigned VarInt at an absolute index without moving the reader, rejecting values
    /// over `limit`.
    ///
    /// See `getVarInt(at:limit:requireMinimal:)`.
    ///
    /// - Parameters:
    ///   - index: The absolute index to decode from.
    ///   - limit: The largest value to accept as a ByteCount.
    ///   - requireMinimal: Whether to reject non-minimal encodings or not.
    /// - Returns: The decoded value and how many bytes it occupies, or `nil` if
    ///   the buffer does not hold a complete VarInt at `index`.
    public func getVarInt(
        at index: Int,
        limit: ByteCount,
        requireMinimal: Bool = true
    ) throws(VarIntError) -> (value: UInt64, byteCount: Int)? {
        try self.getVarInt(at: index, limit: UInt64(clamping: limit.value), requireMinimal: requireMinimal)
    }
}
