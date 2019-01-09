//
//  Service.swift
//  ElementalController
//
//  Created by Rob Reuss on 12/6/18.
//  Copyright © 2019 Rob Reuss. All rights reserved.
//

import Foundation
#if os(Linux)
import NetService
#endif
import Socket

public class ServiceEvent {
    var handlers: Array<((ServiceEvent, ClientDevice) -> Void)?> = []
    
    var type: ServiceEventTypes.EventType // For logging purposes
    
    init(type: ServiceEventTypes.EventType) {
        self.type = type
    }
    
    public typealias EventHandler = (ServiceEvent, ClientDevice) -> Void
    
    func executeHandlers(device: ClientDevice) {
        for handler in handlers {
            if Thread.isMainThread {
                handler!(self, device)
            } else {
                (DispatchQueue.main).sync {
                    handler!(self, device)
                }
            }
        }
    }
    
    public func addHandler(handler: @escaping EventHandler) {
        handlers.append(handler)
    }
}

public class ServiceEventTypes {
    var handlers: Array<((Service, Device) -> Void)?> = []
    // var type: ServiceEventTypes.EventType // For logging purposes
    
    init() {
        logDebug("Service event types initialized")
    }
    
    public enum EventType {
        case onDeviceConnected
        case onDeviceDisconnected
        case onServicePublished
        case onServerListening
        
        private var description: String {
            switch self {
            case .onDeviceConnected: return "Device Connected"
            case .onDeviceDisconnected: return "Device Disconnected"
            case .onServicePublished: return "Service Published"
            case .onServerListening: return "Server Listening"
            }
        }
    }
    
    public var onDeviceConnected = ServiceEvent(type: .onDeviceConnected)
    public var onDeviceDisconnected = ServiceEvent(type: .onDeviceDisconnected)
    public var onServicePublished = ServiceEvent(type: .onServicePublished)
    public var onServerListening = ServiceEvent(type: .onServerListening)
    
    public typealias ServiceEventHandler = (Service, Device) -> Void
    
    public func addHandler(handler: @escaping ServiceEventHandler) {
        handlers.append(handler)
    }
}

// This is Master

// TODO: Add a "how this works" to the header area!

protocol ServiceDelegate {
    func startUDPService(onPort: Int)
    func sendUDPIdentififerToDevice(device: ClientDevice)
    var port: Int { get set }
    func deviceConnected(device: ClientDevice)
    func deviceDisconnected(device: ClientDevice)
}

public class Service: ServiceDelegate {
    var udpService: UDPService?
    var tcpService: TCPService?
    var publisher: Publisher?
    
    // Keeps a hash of client devices and their udpIdentifier (and to assign udpIdentifier)
    var devices: Dictionary<UInt8, ClientDevice> = [:]
    
    var tcpServiceDevice: ServiceDevice?
    var udpServiceDevice: ServiceDevice?
    var port: Int = 0
    
    var serviceName: String = ""
    var isPublished: Bool = false
    var displayName: String = ""
    
    public var events: ServiceEventTypes
    
    // TODO: Need to make locks configurable?
    let deviceIDLockQueue = DispatchQueue(label: "net.simplyformed.deviceIDLockQueue")
    
    init() {
        events = ServiceEventTypes()
    }
    
    func setup(serviceName: String, displayName: String) {
        self.serviceName = serviceName
        self.displayName = displayName
        logDebug("\(formatServiceNameForLogging(serviceName: serviceName)) Server initialized")
        tcpServiceDevice = ServiceDevice(service: self, serviceName: serviceName, displayName: displayName)
        udpServiceDevice = ServiceDevice(service: self, serviceName: serviceName, displayName: displayName)
    }
    
    public func shutdown() {
        logDebug("\(formatServiceNameForLogging(serviceName: serviceName)) Shutting down service")
        for device: ClientDevice in devices.values {
            logDebug("\(formatServiceNameForLogging(serviceName: serviceName)) Device TCP client being shutdown: \(device.displayName)")
            device.shutdownMessageElement.value = "Shutting down services"
            _ = device.send(element: (device.shutdownMessageElement))
            device.tcpClient?.shutdown()
        }
        usleep(1000) // Let the shutdown messages get processed
        udpService!.shutdown()
        tcpService!.shutdown()
        publisher?.stop()
        devices.removeAll() // Clear out the dictionary of devices used for UDP ids
    }
    
    // Start the TCP service - this will give us an assigned port if passed a zero value
    public func publish(onPort: Int) {
        tcpService = TCPService(parentServer: self)
        tcpService!.listenForConnections(onPort: onPort)
    }
    
    // Advertise the TCP service
    func publishTCPServiceAdvertisment(onPort: Int) {
        publisher = Publisher(delegate: self)
        publisher!.start(serviceName: serviceName, displayName: displayName, proto: .tcp, onPort: onPort)
    }
    
    // Start up the UDP Service once we have the port (static or dynamic)
    func startUDPService(onPort: Int) {
        if ElementalController.allowUDPService {
            if udpService == nil {
                udpService = UDPService(service: self)
                udpService!.listenForConnections(onPort: onPort)
            }
        }
    }
    
    func clientDeviceConnectedOn(socket: Socket) {
        let device = ClientDevice(service: self, serviceName: serviceName, displayName: displayName)
        device.tcpClient = TCPClient(device: device, socket: socket)
        device.address = socket.remoteHostname
        device.tcpClient!.run()
        device.serviceName = serviceName
        addDevice(device: device)
        sendUDPIdentififerToDevice(device: device)
        deviceConnected(device: device)
    }
    
    func deviceConnected(device: ClientDevice) {
        logDebug("\(prefixForLoggingServiceNameUsing(device: device)) Device connected.")
        events.onDeviceConnected.executeHandlers(device: device)
    }
    
    func deviceDisconnected(device: ClientDevice) {
        logDebug("\(prefixForLoggingServiceNameUsing(device: device)) Device disconnected.")
        devices.removeValue(forKey: device.udpIdentifier)
        events.onDeviceDisconnected.executeHandlers(device: device)
    }
    
    // Once a device representing the client is created, send the UDP identififer
    func sendUDPIdentififerToDevice(device: ClientDevice) {
        logDebug("\(prefixForLoggingServiceNameUsing(device: device)) Sending UDP identifier: \(device.udpIdentifier)")
        device.udpIdentifierElement.value = device.udpIdentifier
        _ = device.send(element: device.udpIdentifierElement)
    }
    
    // All devices kept here for use by the UDP Server in
    // identifying messages to services.  Assigns udpIdentifier.
    func addDevice(device: ClientDevice) {
        logDebug("\(prefixForLoggingServiceNameUsing(device: device)) Adding device to collection for UDP identification")
        
        var udpID: UInt8 = 1
        
        deviceIDLockQueue.sync {
            while udpID < UInt8.max - 1 {
                if devices.keys.contains(udpID) {
                    udpID += 1
                    continue
                    
                } else {
                    devices[udpID] = device
                    device.udpIdentifier = udpID
                    break
                }
            }
        }
    }
    
    func getDeviceForUDPIdentififer(udpIdentifier: UInt8) -> ClientDevice? {
        guard let device = devices[udpIdentifier] else {
            return nil
        }
        return device
    }
}

class Publisher: NSObject, NetServiceDelegate {
    var udpServiceDevice: ServiceDevice?
    
    var port: Int = 0
    
    var delegate: ServiceDelegate
    var netService: NetService?
    var serviceName: String = ""
    
    init(delegate: ServiceDelegate) {
        self.delegate = delegate
        super.init()
    }
    
    deinit {
        logVerbose("TCP pubishler deinit")
    }
    
    func start(serviceName: String, displayName: String, proto: Proto, onPort: Int) {
        netService = NetService(domain: ElementalController.serviceDomain, type: ElementalController.serviceType(serviceName: serviceName, proto: proto), name: displayName, port: Int32(onPort))
        
        logDebug("\(prefixForLogging(serviceName: serviceName, proto: .tcp)) Publishing as type \(ElementalController.serviceType(serviceName: serviceName, proto: .tcp)) on domain \(ElementalController.serviceDomain) port \(netService!.port) with name \"\(displayName)\"")
        netService?.delegate = self
        
        self.serviceName = serviceName
        
        netService?.publish()
    }
    
    public func netServiceDidPublish(_ sender: NetService) {
        logDebug("Service \(serviceName) is now published")
    }
    
    func stop() {
        logDebug("\(prefixForLogging(serviceName: serviceName, proto: .tcp)) Shutting down TCP service publisher")
        netService?.stop()
    }
    
    public func netServiceWillPublish(_ sender: NetService) {
        logVerbose("\(prefixForLogging(serviceName: serviceName, proto: .tcp)) Service will publish: \(sender.type)")
    }
    
    public func netServiceWillResolve(_ sender: NetService) {
        logVerbose("\(prefixForLogging(serviceName: serviceName, proto: .tcp)) Service will resolve: \(sender.type)")
    }
    
    public func netServiceDidResolveAddress(_ sender: NetService) {
        logVerbose("\(prefixForLogging(serviceName: serviceName, proto: .tcp)) Service did resolve address: \(sender.type)")
    }
    
    public func netService(_ sender: NetService, didUpdateTXTRecord data: Data) {
        logVerbose("\(prefixForLogging(serviceName: serviceName, proto: .tcp)) Service did update TXT record: \(sender.type)")
    }
    
    // TODO: Need to add a handler or notification for this, and/or turn off servers if this happens?  Maybe not,
    // because a user might not care if they're using static IP addresses?
    public func netService(_ sender: NetService, didNotPublish errorDict: [String: NSNumber]) {
        logError("\(prefixForLogging(serviceName: serviceName, proto: .tcp)) Service did not publish: \(sender.type): \(errorDict)")
    }
    
    public func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        logError("\(prefixForLogging(serviceName: serviceName, proto: .tcp)) Service did not resolve: \(sender.type)")
    }
    
    public func netServiceDidStop(_ sender: NetService) {
        logDebug("\(prefixForLogging(serviceName: serviceName, proto: .tcp)) Publishing service stopped: \(serviceName)")
    }
}
