// swift-tools-version:5.5
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

import PackageDescription

let package = Package(
    name: "swift-libp2p-core",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13)
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "LibP2PCore",
            targets: ["LibP2PCore"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.

        // Swift NIO for all things networking
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.0.0"),
        
        // LibP2P Peer Identities
        .package(url: "https://github.com/swift-libp2p/swift-peer-id.git", from: "0.0.1"),
        
        // LibP2P Multiaddr
        .package(url: "https://github.com/swift-libp2p/swift-multiaddr.git", from: "0.0.1"),
        
        // Logging
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        
        // Swift Protobuf
        //.package(url: "https://github.com/apple/swift-protobuf.git", .exact("1.19.0")),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "LibP2PCore",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "PeerID", package: "swift-peer-id"),
                .product(name: "Multiaddr", package: "swift-multiaddr"),
                //.product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]),
        .testTarget(
            name: "LibP2PCoreTests",
            dependencies: ["LibP2PCore"]),
    ]
)
