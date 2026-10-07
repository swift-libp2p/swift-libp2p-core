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

import Testing

@testable import LibP2PCore

@Suite("Libp2p Core Tests")
struct LibP2PCoreTests {
    @Test func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct
        // results.
        //XCTAssertEqual(swift_libp2p_core().text, "Hello, World!")
    }
}

@Suite("Connection Status Tests")
struct ConnectionStatusTests {
    /// Connections accept new streams until they start closing.
    @Test(arguments: [
        (ConnectionStats.Status.opening, true),
        (.open, true),
        (.upgraded, true),
        (.closing, false),
        (.closed, false),
    ])
    func acceptsNewStreams(_ status: ConnectionStats.Status, _ expected: Bool) {
        #expect(status.acceptsNewStreams == expected)
    }
}
