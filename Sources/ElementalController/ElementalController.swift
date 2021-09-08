//
//  ElementalController.swift
//  ElementalController
//
//  Created by Rob Reuss on 12/15/18.
//  Copyright © 2019 Rob Reuss. All rights reserved.
//

// Implementation notes:
// udpIdentifier of MAX is a bogus value for a TCP transmission

import Foundation
import Socket
#if os(iOS) || os(tvOS)
import UIKit
#endif
#if os(Linux)
import Dispatch
import Glibc
import NetService
#endif

let NETSERVICE_RESOLVE_TIMEOUT = 5.0

public enum Proto {
    case tcp
    case udp
    
    var description: String {
        switch self {
        case .tcp: return "tcp"
        case .udp: return "udp"
        }
    }
}

public class ElementalController {
    
    // Remote Logging
    public static var remoteLogging = RemoteLogging()
    
    // Currently framework is only tested for private LAN use so this shouldn't be changed unless you're daring
    public static var serviceDomain = "local." {
        didSet {
            logDebug("Service domain set to: \(serviceDomain)")
        }
    }
    
    // Amount of data fetched from the socket per cycle.  Make larger or smaller based on typical message size
    public static var TCPBufferSize = 4096 {
        didSet {
            logDebug("TCP buffer size set to: \(TCPBufferSize)")
        }
    }
    public static var UDPBufferSize = 512 {
        didSet {
            logDebug("UDP buffer size set to: \(UDPBufferSize)")
        }
    }
    
    // What if anything precedes log lines to it's clear the lines are coming from the framework
    public static var loggerPrefix = "EC" {
        didSet {
            logDebug("Logger prefix set to: \(loggerPrefix)")
        }
    }
    
    // Frequency transfer analysis stats should be calculated and displayed
    public static var transferAnalysisFrequency: Float = 10.0 {
        didSet {
            logDebug("Transfer analysis frequency set to: \(transferAnalysisFrequency)")
        }
    }
    
    // Transfer analysis logs information about the performance of network and message processing
    public static var enableTransferAnalysis = false {
        didSet {
            logDebug("Transfer analysis: \(enableTransferAnalysis)")
        }
    }
    
    // An arbitrary number used to identify the start of an element message.
    // Not required, just a mechanism to keep messages aligned.
    public static var headerIdentifier: UInt32 = 2584594329  {
        didSet {
            logDebug("Header identifier set to: \(headerIdentifier)")
            logError("Header identifier depracated")
        }
    }
    
    public static var requireHeaderIdentifier = false {
        didSet {
            logDebug("Require header identifier: \(requireHeaderIdentifier)")
            logError("Header identifier depracated")
        }
    }
    
    public static var protocolFamily: Socket.ProtocolFamily = Socket.ProtocolFamily.inet {
        didSet {
            logDebug("Protocol family set to: \(protocolFamily)")
        }
    }
    
    
    // If UDP server is disabled, we intentionally crash if a UDP element is added.
    // This may be preferred becuase UDP is so open, although in our implementation so
    // is TCP at this point.
    public static var allowUDPService = true {
        didSet {
            logDebug("Allow UDP service: \(allowUDPService)")
        }
    }
    
    // Each instance use of the framework will employ one or both of these mechanisms:
    // Browser provides the basis of client functionality
    // Service provides the basis of server functionality
    public var browser = Browser()
    public var service = Service()

    public init() {}
    
    // First method called for setting up a service, provides a Service
    // instance to which the user can add handlers.  Service isn't published
    // until the "publish" method on Service is called.
    public func setupForService(serviceName: String, displayName: String) {
        service.setup(serviceName: serviceName, displayName: displayName.count == 0 ? ElementalController.machineName : displayName)
    }
    
    public func stopService() {
        service.stopService()
    }
    
    // Initialize the browser, and then next would call the "browse" method
    // on Browser.
    public func setupForBrowsingAs(deviceNamed: String) {
        browser.setup(named: deviceNamed)
    }
    
    // Connect to a known service
    /// Used as an alternative to Zeroconf service discovery when the
    /// identity, hostname and port of a service is already known.
    /// The foundServer event will still fire wherein element handlers
    /// should be defined for that service.
    /// - Parameters:
    ///   - named: The short (not the display name) of a service (e.g. "robot")
    ///   - atHost: Host name on the LAN, either a host name or IP address.
    ///   - onPort: The port the service is published on at the hostname.
    public func connectToService(named: String, atHost: String, onPort: Int) {
        logDebug("\(prefixForLogging(serviceName: named, proto: .tcp)) Connecting to host \(atHost) on port \(onPort)")
        browser.setupServerDevicefor(aServiceName: named, withDisplayName: named, atHost: atHost, onPort: onPort)
    }
    
    // Convienance function to define service type for NetService
    static func serviceType(serviceName: String, proto: Proto) -> String {
        return "_\(serviceName)._\(proto)."
    }
    
    // TODO: Fix the Linux side of this
    public static var machineName: String {
        #if os(iOS)
        return UIDevice.current.name
        #endif
        
        #if os(macOS)
        return Host.current().localizedName!
        #endif
        
        #if os(Linux)
        
        // TODO: Fix handling of failed access
        do {
            return "Undefined name"
        } catch {}
        
        return ""
        
        #endif
    }
    
    /// Log Level "Debug" is a standard level of logging for debugging - set to "Error" for release
    public static var loggerLogLevel: LogLevel = LogLevel.Debug {
        didSet {
            logDebug("Set logLevel: \(ElementalController.loggerLogLevel)")
        }
    }
    
    /// Use either NSLog or Swift "print" for logging - NSLog gives more detail
    public static var loggerUseNSLog: Bool = false {
        didSet {
            logDebug("Set NSLog logging to: \(ElementalController.loggerUseNSLog)")
        }
    }
    
    deinit {
        logDebug("ElementController deinit")
    }
}
