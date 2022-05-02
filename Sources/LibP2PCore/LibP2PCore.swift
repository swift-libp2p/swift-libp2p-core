@_exported import NIOCore
@_exported import Multiaddr
@_exported import PeerID
@_exported import Multibase
@_exported import Multicodec
@_exported import Foundation
@_exported import VarInt

//public protocol Codecs { }

public enum Mode:String {
    case initiator
    case listener
}
