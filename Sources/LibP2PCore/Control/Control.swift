//
//  Control.swift
//  
//
//  Created by Brandon Toms on 3/8/22.
//

/// DisconnectReason communicates the reason why a connection is being closed.
///
/// A zero value stands for "no reason" / NA.
///
/// This is an EXPERIMENTAL type. It will change in the future. Refer to the
/// connmgr.ConnectionGater godoc for more info.
public enum DisconnectReason:Int {
    case noReason = 0
}
