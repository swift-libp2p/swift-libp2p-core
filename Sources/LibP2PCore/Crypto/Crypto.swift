//
//  Crypto.swift
//  
//
//  Created by Brandon Toms on 3/8/22.
//

/// PrivKey represents a private key that can be used to generate a public key and sign data
public protocol PrivateKey {
    var key:[UInt8] { get }

    /// Cryptographically sign the given bytes
    func sign(_ data:[UInt8]) throws -> [UInt8]

    /// Return a public key paired with this private key
    func getPublicKey() throws -> PublicKey
}

/// PubKey is a public key that can be used to verifiy data signed with the corresponding private key
public protocol PublicKey {
    var key:[UInt8] { get }

    /// Verify that 'sig' is the signed hash of 'data'
    func verify(data:[UInt8], againstSignature:[UInt8]) throws -> Bool
    
    init(fromMarshaledValue:[UInt8]) throws
}
