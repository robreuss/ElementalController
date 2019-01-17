//
//  Errors.swift
//  ElementalController
//
//  Created by Rob Reuss on 1/16/19.
//  Copyright © 2019 Rob Reuss. All rights reserved.
//

import Foundation

public enum ElementSendError: Error {
    case attemptToDisallowUDP
    case attemptToSendNoConnection
    case attemptToSendNoUDPClient
    case attemptToSendNoTCPClient
    case attemptToSendWithNoUDPSocket
    case attemptToSendWithNoTCPSocket
    case attemptToSendWithUDPError
    case attemptToSendTCPServiceIsStopped
}
