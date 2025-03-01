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

/// PrivKey represents a private key that can be used to generate a public key and sign data
public protocol PrivateKey {
    var key: [UInt8] { get }

    /// Cryptographically sign the given bytes
    func sign(_ data: [UInt8]) throws -> [UInt8]

    /// Return a public key paired with this private key
    func getPublicKey() throws -> PublicKey
}

/// PubKey is a public key that can be used to verifiy data signed with the corresponding private key
public protocol PublicKey {
    var key: [UInt8] { get }

    /// Verify that 'sig' is the signed hash of 'data'
    func verify(data: [UInt8], againstSignature: [UInt8]) throws -> Bool

    init(fromMarshaledValue: [UInt8]) throws
}
