//
//  Elemental Controller.swift
//  Elemental Controller
//
//  Created by Rob Reuss on 12/15/18.
//  Copyright © 2018 Rob Reuss. All rights reserved.
//

// Implementation notes:
// udpIdentifier of MAX is a bogus value for a TCP transmission

import Foundation
import Socket
#if os(Linux)
import Dispatch
import Glibc
import NetService
#endif

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

    // User confirmation options
    public static var serviceDomain = "local."              // Currently framework is only tested for private LAN use so this shouldn't be changed
    public static var TCPBufferSize = 4096                  // Amount of data fetched from the socket per cycle.  Make larger or smaller based on typical message size
    public static var UDPBufferSize = 512                   // Same.
    public static var loggerPrefix = "EC"                   // What if anything precedes log lines to it's clear the lines are coming from the framework
    public static var transferAnalysisFrequency: Float = 10.0  // Frequency transfer analysis stats should be calculated and displayed
    public static var enableTransferAnalysis = false        // Transfer analysis logs information about the performance of network and message processing
    
    // An arbitrary number used to identify the start of an element message.
    // Not required, just a mechanism to keep messages aligned.
    public static var headerIdentifier: UInt32 = 2584594329
    public static var requireHeaderIdentifier = true
    
    // If UDP server is disabled, we intentionally crash if a UDP element is added.
    // This may be preferred becuase UDP is so open, although in our implementation so
    // is TCP at this point.
    public static var allowUDPService = true
    
    // Each instance use of the framework will employ one or both of these mechanisms:
    // Browser provides the basis of client functionality
    // Service provides the basis of server functionality
    public var browser = Browser()
    public var service = Service()

    // TODO: Not sure implemented, not sure should be
    public static var useRandomServiceName = false
    
    public init() {}

    // First method called for setting up a service, provides a Service
    // instance to which the user can add handlers.  Service isn't published
    // until the "publish" method on Service is called.
    public func setupForService(serviceName: String, displayName: String) {
        service.setup(serviceName: serviceName, displayName: displayName.count == 0 ? ElementalController.machineName : displayName)
    }
    
    public func stopService() {
         service.shutdown()
     }
    
    // Initialize the browser, and then next would call the "browse" method
    // on Browser.
    public func setupForBrowsingAs(deviceNamed: String) {
        browser.setup(named: deviceNamed)
    }

    // Skip browsing directly connect on a specific port
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
            
            #if os(OSX)
            return Host.current().localizedName!
            #endif
            
            #if os(Linux)
            
            // TODO: Fix handling of failed access
            do {
                return "Undefined service name"
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
