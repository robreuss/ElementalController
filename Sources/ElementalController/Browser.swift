//
//  Browser.swift
//  ElementalController
//
//  Created by Rob Reuss on 12/6/18.
//  Copyright © 2019 Rob Reuss. All rights reserved.
//
//  Classes related to service discovery

import Dispatch
import Foundation

#if os(Linux)
import NetService
#endif

// Test comment

// Event handling for the browser

public class BrowserEvent {
    var type: BrowserEventTypes.EventType
    
    public typealias BrowserHandler = ((ServerDevice) -> Void)
    private var privateHandler: BrowserHandler?
    
    init(type: BrowserEventTypes.EventType) {
        self.type = type
    }
    
    func executeHandler(serverDevice: ServerDevice) {
        guard let h = privateHandler else { return }
        if Thread.isMainThread {
            h(serverDevice)
        } else {
            (DispatchQueue.main).sync {
                h(serverDevice)
            }
        }
    }
    
    public var handler: BrowserHandler? {
        set {
            privateHandler = newValue
        }
        get {
            return privateHandler
        }
    }
    
    public func handler(handler: @escaping BrowserHandler) {
        privateHandler = handler
    }
}

public class BrowserEventTypes {
    public enum EventType {
        case foundServer
        
        private var description: String {
            switch self {
            case .foundServer: return "Found Server"
            }
        }
    }
    
    public var foundServer = BrowserEvent(type: .foundServer)
}


// Provide user with the ability to find advertised services
public class Browser: NSObject, NetServiceDelegate {
    var serviceName: String = ""
    
    // References to the underlying frameworks for service discovery.
    // Note that "NetService" is either the Apple framework or the
    // third-party Linux module that provides the same interface.
    var browser = NetServiceBrowser()
    var netService: NetService?
    
    // Set on the client side, it is sent to the server once
    // a connection is established in case the server needs
    // to display it
    var browserName: String = ElementalController.machineName
    
    // Created when a connection established, this is the main
    // interface to the server for the client
    var serverDevice: [String: ServerDevice] = [:]
    
    // Used for logging purposes
    var proto: Proto = .tcp
    
    // Used to prevent multiple attempts to resolve the same service
    var resolvingService = false
    
    // Used to prevent needlessly starting/stopping the browsing service
    public var isBrowsing = false
    
    public var events = BrowserEventTypes()
    
    override init() {
        super.init()
    }
    
    deinit {
        logDebug("Browser deinitialized")
    }

    // Called by the user via a property on Elemental Controller prior
    // to setting up handlers
    // TODO: Give same signature os the EC version
    func setup(named: String) {
        if named.count > 0 {
            browserName = named
        } else {
            browserName = ElementalController.machineName
        }
        events = BrowserEventTypes()
        browser.delegate = self
        isBrowsing = false
    }
    
    // Kick off the browsing process
    public func browseFor(serviceName: String) {
        self.serviceName = serviceName
        startBrowsing()
    }
    
    // It is not necessary for the user to call this during the
    // normal flow - it's called automatically when a connection is made
    public func stopBrowsing() {
        if isBrowsing == true {
            logDebug("\(formatServiceNameForLogging(serviceName: serviceName)) Stopping browsing for \(serviceName)")
            browser.stop()
            resolvingService = false
            isBrowsing = false
        } else {
            logDebug("\(formatServiceNameForLogging(serviceName: serviceName)) Stop browsing called when not browsing")
        }
    }
    
    // Private function for starting browsing process
    // TODO: should just be integrated into the browseFor method above
    func startBrowsing() {
        if isBrowsing {
            logDebug("\(formatServiceNameForLogging(serviceName: serviceName)) startBrowsing called when already browsing for service of type: \(ElementalController.serviceType(serviceName: serviceName, proto: proto)) in domain: \(ElementalController.serviceDomain)")
        } else {
            logDebug("\(formatServiceNameForLogging(serviceName: serviceName)) Browsing for service of type: \(ElementalController.serviceType(serviceName: serviceName, proto: proto)) in domain: \(ElementalController.serviceDomain)")
            isBrowsing = true
            browser.searchForServices(ofType: ElementalController.serviceType(serviceName: serviceName, proto: proto), inDomain: ElementalController.serviceDomain)
        }
    }
    
    // Called when a connection is made, executes the foundServer handler
    func setupServerDevicefor(aServiceName: String, withDisplayName: String, atHost: String, onPort: Int) {
        serverDevice[aServiceName] = ServerDevice(serviceName: aServiceName, displayName: withDisplayName)
        if let serverDevice = serverDevice[aServiceName] {
            serverDevice.deviceName = browserName
            serverDevice.remoteServerAddress = atHost
            serverDevice.remoteServerPort = onPort
            events.foundServer.executeHandler(serverDevice: serverDevice)
        }
    }
    

}

// These are the standard NetServiceBrowser callbacks (for both the Apple
// and Linux versions
extension Browser: NetServiceBrowserDelegate {
    
    // Found a service, start resolving...
    public func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        logDebug("\(formatServiceNameForLogging(serviceName: serviceName)) Browser found service of type \(service.type)")
        if moreComing {
            logDebug("\(formatServiceNameForLogging(serviceName: serviceName)) Ignoring \(service.type) because more services coming (prefer IPV6...")
            return
        }
        if resolvingService == false  {
            resolvingService = true
            logDebug("\(formatServiceNameForLogging(serviceName: serviceName)) Resolving service \(service.type)...")
            netService = service
            netService?.delegate = self
            netService?.resolve(withTimeout: NETSERVICE_RESOLVE_TIMEOUT)
        } else {
            logDebug("\(formatServiceNameForLogging(serviceName: serviceName)) Not resolving service \(service.type), already resolving a service")
        }
    }

    // Resolved a service, execute foundServer handler above
    public func netServiceDidResolveAddress(_ sender: NetService) {
        if resolvingService == false {
            logDebug("\(formatServiceNameForLogging(serviceName: serviceName)) Ignoring resolution of service name \"\(sender.name)\" because resolution was cancelled.")
        } else {
            if let hostName = sender.hostName {
                logDebug("\(formatServiceNameForLogging(serviceName: serviceName)) Browser successfully resolved address: \(hostName): \(sender.port), service name: \(serviceName) display name: \"\(sender.name)\"")
            } else {
                logDebug("\(formatServiceNameForLogging(serviceName: serviceName)) Browser successfully resolved (unknown host name)")
            }
            setupServerDevicefor(aServiceName: serviceName, withDisplayName: sender.name, atHost: sender.hostName!, onPort: sender.port)
            stopBrowsing()
        }
    }
    
    // NetService Stubs
    public func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        logVerbose("\(formatServiceNameForLogging(serviceName: serviceName)) Browser will search")
    }
    
    public func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        logVerbose("\(formatServiceNameForLogging(serviceName: serviceName)) Browser did stop search")

        // ElementalController.events.browsingStopped.executeHandlers(contextInfo: ["serviceName": serviceName])
    }
    
    // TODO: Need to handle this more substantially, providing feedback to the user so they
    // can restart the search
    public func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        logVerbose("\(formatServiceNameForLogging(serviceName: serviceName)) Browser did not search: \(errorDict)")
        // self.events.browsingError.executeHandlers(contextInfo: ["serviceName": serviceName, "error": errorDict])
        stopBrowsing()
    }
    
    // TODO: Need to handle this more substantially, providing feedback to the user so they
    // can restart the search
    public func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        logVerbose("\(formatServiceNameForLogging(serviceName: serviceName)) Browser did not resolve: \(errorDict)")
        stopBrowsing()
        // self.events.browsingError.executeHandlers(contextInfo: ["serviceName": serviceName, "error": errorDict])
    }
    
    // Linux versions (error is an Error type rather than a dictionary)
    public func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch error: Error) {
        logVerbose("\(formatServiceNameForLogging(serviceName: serviceName)) Browser did not search: \(error)")
        // self.events.browsingError.executeHandlers(contextInfo: ["serviceName": serviceName, "error": error])
    }
    
    public func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        logVerbose("\(formatServiceNameForLogging(serviceName: serviceName)) Browser did remove service")
        // ElementalController.events.browsingStopped.executeHandlers(contextInfo: ["serviceName": serviceName])
    }
    
    public func netServiceBrowser(_ browser: NetServiceBrowser, didFindDomain domainString: String, moreComing: Bool) {
        logVerbose("\(formatServiceNameForLogging(serviceName: serviceName)) Browser did find domain")
    }
    
    public func netServiceBrowser(_ browser: NetServiceBrowser, didRemoveDomain domainString: String, moreComing: Bool) {
        logVerbose("\(formatServiceNameForLogging(serviceName: serviceName)) Browser did remove domain")
    }
    
    // TODO: Decide whether to include this because I don't think it's supported by Apple and is only planned for the Linux version
    //
    func netServiceDidNotResolve(_ sender: NetService, error: Error) {
        logVerbose("\(formatServiceNameForLogging(serviceName: serviceName)) Failed to resolve server \(sender.type)")
    }
    
}
