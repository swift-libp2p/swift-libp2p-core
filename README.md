# LibP2PCore

[![](https://img.shields.io/badge/made%20by-Breth-blue.svg?style=flat-square)](https://breth.app)
[![](https://img.shields.io/badge/project-libp2p-yellow.svg?style=flat-square)](http://libp2p.io/)
[![Swift Package Manager compatible](https://img.shields.io/badge/SPM-compatible-blue.svg?style=flat-square)](https://github.com/apple/swift-package-manager)
![Build & Test (macos and linux)](https://github.com/swift-libp2p/swift-libp2p-core/actions/workflows/build+test.yml/badge.svg)

> The core LibP2P Interfaces / Protocols and Abstractions backing the swift-libp2p project

## Table of Contents

- [Overview](#overview)
- [Install](#install)
- [Usage](#usage)
  - [Example](#example)
  - [API](#api)
- [Contributing](#contributing)
- [Credits](#credits)
- [License](#license)

## Overview
LibP2PCore is a repository / dependency that houses the building blocks for swift-libp2p.

#### Note:
- For more information check out the [LibP2P Spec](https://github.com/libp2p/specs)

## Install

Include the following dependency in your Package.swift file
```Swift
let package = Package(
    ...
    dependencies: [
        ...
        .package(name: "LibP2PCore", url: "https://github.com/swift-libp2p/swift-libp2p-core.git", .upToNextMajor(from: "0.0.1"))
    ],
        ...
        .target(
            ...
            dependencies: [
                ...
                .product(name: "LibP2PCore", package: "swift-libp2p-core"),
            ]),
        ...
    ...
)
```

## Usage

### Example 
check out the [tests]() for more examples

```Swift

import LibP2PCore

// You now have access to thing like PeerID, Multiaddr, Connections, Swift-NIO, etc...

```

### API
```Swift
Not Applicable
```

## Contributing

Contributions are welcomed! This code is very much a proof of concept. I can guarantee you there's a better / safer way to accomplish the same results. Any suggestions, improvements, or even just critques, are welcome! 

Let's make this code better together! 🤝

[![](https://cdn.rawgit.com/jbenet/contribute-ipfs-gif/master/img/contribute.gif)](https://github.com/ipfs/community/blob/master/contributing.md)

## Credits

- [LibP2P Spec](https://github.com/libp2p/specs)

## License

[MIT](LICENSE) © 2022 Breth Inc.

