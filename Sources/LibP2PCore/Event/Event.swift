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

/// Any Event that gets passed into / over the Eventbus must conform to this Event protocol
public protocol Event {}

// The empty `EventBus` placeholder protocol was removed in 0.6.0
// The event-bus abstraction lives at the application layer for now.
// public protocol EventBus {}
