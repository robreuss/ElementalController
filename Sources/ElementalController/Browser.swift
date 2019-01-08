//
//  Browser.swift
//  Elemental Controller
//
//  Created by Rob Reuss on 12/6/18.
//  Copyright © 2018 Rob Reuss. All rights reserved.
//

import Dispatch
import Foundation

#if os(Linux)
import NetService
#endif

public class BrowserEvent {

    var type: BrowserEventTypes.EventType
    
    public typealias BrowserHandler = ((ServerDevice) -> Void)?
    private var privateHandler: BrowserHandler
    
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
    
    public func handler(handler: BrowserHandler) {
        privateHandler = handler
    }

}


public class BrowserEventTypes {

    public enum EventType {
        
        case onFoundServer
        
        private var description: String {
            switch self {
            case .onFoundServer: return "Found Server"
            }
        }
    }
    
    public var onFoundServer = BrowserEvent(type: .onFoundServer)
    
}


public class Browser: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    
    var serviceName: String = ""
    var browser = NetServiceBrowser()
    var netService: NetService?
    var browserName: String = ElementalController.machineName
    var serverDevice: Dictionary<String, ServerDevice> = [:]
    var proto: Proto = .tcp
    
    public var events = BrowserEventTypes()

    override init() {
        super.init()
    }
    
    deinit {
        logDebug("Browser deinitialized")
    }
    
    func setup(named: String) {
        if named.count > 0 {
            self.browserName = named
        } else {
            self.browserName = ElementalController.machineName
        }
        self.events = BrowserEventTypes()
        browser.delegate = self
    }
    
    public func browse(serviceName: String) {

        self.serviceName = serviceName
        startBrowsing()
        
    }
    
    public func stopBrowsing() {
        logDebug("\(formatServiceNameForLogging(serviceName: serviceName)) Stopping browsing for \(serviceName)")
        browser.stop()
    }
    
    func startBrowsing() {
        logDebug("\(formatServiceNameForLogging(serviceName: serviceName)) Browsing for service of type: \(ElementalController.serviceType(serviceName: serviceName, proto: proto)) in domain: \(ElementalController.serviceDomain)")
        
        #if os(Linux)
        withExtendedLifetime((browser, self)) {
            RunLoop.main.run()
        }
        #endif
        
        browser.searchForServices(ofType: ElementalController.serviceType(serviceName: serviceName, proto: proto), inDomain: ElementalController.serviceDomain)
    }
    
    public func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        logDebug("\(formatServiceNameForLogging(serviceName: serviceName)) Browser found service of type \(service.type), resolving address...")
        
        netService = service
        netService?.delegate = self
        netService?.resolve(withTimeout: 5.0) // TODO: Make this value configurable
    }
    
    
    func setupServerDevicefor(aServiceName: String, withDisplayName: String, atHost: String, onPort: Int) {
        
        self.serverDevice[aServiceName] = ServerDevice(serviceName: aServiceName, displayName: withDisplayName)
        if let serverDevice = self.serverDevice[aServiceName] {
            serverDevice.deviceName = self.browserName
            serverDevice.remoteServerAddress = atHost
            serverDevice.remoteServerPort = onPort
            self.events.onFoundServer.executeHandler(serverDevice: serverDevice)
        }
    }
    
    
    public func netServiceDidResolveAddress(_ sender: NetService) {
        if let hostName = sender.hostName {
            logDebug("\(formatServiceNameForLogging(serviceName: serviceName)) Browser successfully resolved address: \(hostName): \(sender.port), service name: \"\(sender.name)\"")
        } else {
            logDebug("\(formatServiceNameForLogging(serviceName: serviceName)) Browser successfully resolved (unknown host name)")
        }

        self.setupServerDevicefor(aServiceName: serviceName, withDisplayName: sender.name, atHost: sender.hostName!, onPort: sender.port)
        stopBrowsing()

    }
    
    // NetService Stubs
    public func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        logVerbose("\(formatServiceNameForLogging(serviceName: serviceName)) Browser will search")
    }
    
    public func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        logVerbose("\(formatServiceNameForLogging(serviceName: serviceName)) Browser did stop search")
        //ElementalController.events.browsingStopped.executeHandlers(contextInfo: ["serviceName": serviceName])
    }
    
    public func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        logVerbose("\(formatServiceNameForLogging(serviceName: serviceName)) Browser did not search: \(errorDict)")
        //self.events.browsingError.executeHandlers(contextInfo: ["serviceName": serviceName, "error": errorDict])
    }
    
    public func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        logVerbose("\(formatServiceNameForLogging(serviceName: serviceName)) Browser did not resolve: \(errorDict)")
         //self.events.browsingError.executeHandlers(contextInfo: ["serviceName": serviceName, "error": errorDict])
    }
    
    // Linux versions (error is an Error type rather than a dictionary)
    public func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch error: Error) {
        logVerbose("\(formatServiceNameForLogging(serviceName: serviceName)) Browser did not search: \(error)")
        //self.events.browsingError.executeHandlers(contextInfo: ["serviceName": serviceName, "error": error])
    }
    
    public func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        logVerbose("\(formatServiceNameForLogging(serviceName: serviceName)) Browser did remove service")
        //ElementalController.events.browsingStopped.executeHandlers(contextInfo: ["serviceName": serviceName])
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
