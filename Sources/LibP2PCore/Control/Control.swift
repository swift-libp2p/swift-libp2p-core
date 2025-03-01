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

/// DisconnectReason communicates the reason why a connection is being closed.
///
/// A zero value stands for "no reason" / NA.
///
/// This is an EXPERIMENTAL type. It will change in the future. Refer to the
/// connmgr.ConnectionGater godoc for more info.
public enum DisconnectReason:Int {
    case noReason = 0
}
