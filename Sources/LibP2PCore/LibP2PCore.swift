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

@_exported import Foundation
@_exported import Multiaddr
@_exported import Multibase
@_exported import Multicodec
@_exported import NIOCore
@_exported import PeerID
@_exported import VarInt

//public protocol Codecs { }

public enum Mode: String, Sendable {
    case initiator
    case listener
}
