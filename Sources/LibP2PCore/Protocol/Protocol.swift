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

import NIOCore
//import Multiaddr
//import PeerID

struct ID {
    static let TestingID = "/p2p/_testing"
}

public protocol LibP2PProtocol {
    var proto:String { get }
    var stringValue:String { get }
    var version:SemanticVersion { get }
}

public protocol SemanticVersion {
    var stringValue:String { get }
}

public struct ProtocolRegistration {
    let proto:SemVerProtocol
    let middleware:[ChannelHandler]
    let transports:[Transport]
    let finalHandler:ProtocolRouteHandler
    let tempHandler:ProtocolHandler
    
    func availableForTransport(_ t:Transport) -> Bool {
        if transports.isEmpty { return true }
        return transports.contains(where: { $0.description == t.description })
    }
    
    public func protocolString() -> String {
        self.proto.stringValue
    }
}

//public struct InboundPayload<T:Any> {
//    let remotePeer:PeerID
//    let remoteAddress:Multiaddr
//    let protocolString:String
//    let protocolVersion:String
//    let payload:T
//}

public final class ProtocolRouteHandler:ChannelInboundHandler {
    public typealias InboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        print("TODO::Implement me...")
    }
}


public protocol ProtocolHandler {
    func handleData(_ data:[UInt8]) -> EventLoopFuture<Void>
    func write(_ data:[UInt8])
}



/// Semantic Versioning 2.0.0
///
/// [Spec](https://semver.org/#semantic-versioning-200)
public struct SemVerProtocol:Equatable {
    public enum SemVersion:Equatable {
        case exact(ProtocolVersion)
        case from(ProtocolVersion)
        case upToNextMinor(ProtocolVersion)
        case upToNextMajor(ProtocolVersion)
        
        public var stringValue:String {
            switch self {
            case .exact(let v):
                return v.stringValue
            case .from(let v):
                return v.stringValue
            case .upToNextMajor(let v):
                return v.stringValue
            case .upToNextMinor(let v):
                return v.stringValue
            }
        }
        
        public var protocolVersion:ProtocolVersion {
            switch self {
            case .exact(let v):
                return v
            case .from(let v):
                return v
            case .upToNextMajor(let v):
                return v
            case .upToNextMinor(let v):
                return v
            }
        }
        
        public func matches(_ pv:ProtocolVersion) -> Bool {
            switch self {
            case .exact(let v):
                // pv must match self exactly
                return v.major == pv.major && v.minor == pv.minor && v.patch == pv.patch
            case .from(let v):
                // Only the major version needs to match
                return v.major == pv.major
            case .upToNextMajor(let v):
                // Only the major version needs to match
                return v.major == pv.major
            case .upToNextMinor(let v):
                // Both the major and minor versions need to match
                return v.major == pv.major && v.minor == pv.minor
            }
        }
        
    }
    
    public struct ProtocolVersion:Equatable {
        let major:Int
        let minor:Int
        let patch:Int
        
        var stringValue:String {
            return "\(major).\(minor).\(patch)"
        }
    }
    
    /// The protocols name (ex: plaintext)
    let proto:String
    /// The protocols version (ex: 2.0.0)
    let version:SemVersion?
    
    /// Instantiates a SemVerProtocol matching the exact version specified
    public init(proto:String, version:ProtocolVersion?) {
        self.proto = proto.hasPrefix("/") ? proto : "/\(proto)"
        if let v = version {
            self.version = .exact(v)
        } else {
            self.version = nil
        }
        
    }
    
    public init(proto:String, version:SemVersion?) {
        self.proto = proto.hasPrefix("/") ? proto : "/\(proto)"
        self.version = version
    }
    
    /// Takes a string of the form "/echo/1.0.0" and turns it into a SemVerProtocol (using the exact version)
    public init?(_ string:String) {
        guard !string.isEmpty && string.count > 1 else { return nil }
        let protoString = string.hasPrefix("/") ? String(string.dropFirst()) : string
        
        var parts = protoString.split(separator: "/")
        
        var semVer:ProtocolVersion? = nil
        if let last = parts.last, last.contains(".") {
            // We have a version
            let numbers = last.split(separator: ".").compactMap { Int($0) }
            guard numbers.count == 3 else { print("Failed to parse Version from proto string '\(string)'"); return nil }
            semVer = ProtocolVersion(major: numbers[0], minor: numbers[1], patch: numbers[2])
            
            parts.removeLast()
        }
        
        self.proto = "/\(parts.joined(separator: "/"))"
        if let v = semVer {
            self.version = .exact(v)
        } else {
            self.version = nil
        }
        
    }
    
    public func matches(_ svp:SemVerProtocol) -> Bool {
        /// Ensure the protocol matches first
        guard proto == svp.proto else { return false }
        /// Now check if the versioning is compatible
        if let v = version {
            // If we specify a version and the SemVerProtocol being compared to doesn't, we return no match.
            guard let vp = svp.version else { return false }
            // If we both specify version, ensure they match
            return v.matches(vp.protocolVersion) || vp.matches(v.protocolVersion)
        } else if svp.version != nil {
            // The SemVerProtocol being compared against specifies a version, while we dont. Lets treat this as a non-match
            return false
        } else {
            // Neither SemVerProtocols specify a version
            return true
        }
    }
    
    public var stringValue:String {
        if let version = version {
            return "\(proto)/\(version.stringValue)"
        } else {
            return "\(proto)"
        }
    }
}
