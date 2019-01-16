//
//  Device.swift
//  ElementalController
//
//  Created by Rob Reuss on 12/6/18.
//  Copyright © 2019 Rob Reuss. All rights reserved.
//

import Foundation
import Socket

public class DeviceEvent {
    var type: DeviceEventTypes.EventType
    
    public typealias DeviceHandler = ((Device) -> Void)?
    public var handler: DeviceHandler?
    
    init(type: DeviceEventTypes.EventType) {
        self.type = type
    }
    
    func executeHandler(device: Device) {
        guard let h = handler else { return }
        guard
        if Thread.isMainThread {
            h!(device)
        } else {
            (DispatchQueue.main).sync {
                h!(device)
            }
        }
    }
    
    deinit {
        logDebug("DeviceEvent deinitialized")
    }
}

public class DeviceEventTypes {
    public enum EventType {
        case deviceDisconnected
        case connectFailed
        case connected
        case serviceFailedToPublish
        
        private var description: String {
            switch self {
            case .deviceDisconnected: return "Device disconnected"
            case .connectFailed: return "Connect failed"
            case .connected: return "Connected"
            case .serviceFailedToPublish: return "Service failed to publish"
            }
        }
    }
    
    public var deviceDisconnected = DeviceEvent(type: .deviceDisconnected)
    public var connectFailed = DeviceEvent(type: .connectFailed)
    public var connected = DeviceEvent(type: .connected)
    public var serviceFailedToPublish = DeviceEvent(type: .serviceFailedToPublish)
    
    deinit {
        logDebug("DeviceEventTypes deinitialized")
    }
}

public class Device {
    // Uniquely identifies a UDP client for the server so we know who are the
    // message is coming from, and supplies a client with the ID they need to
    // send to the UDP server to identify themselves.
    var udpIdentifier: UInt8 = 0
    
    // Both server and client implementions have a TCPClient that
    // provides TCP connectivity...
    var tcpClient: TCPClient?
    
    // Handles the initiation of the connection to the client
    // to the service
    var tcpClientConnector: TCPClientConnector?
    
    // Each type of network connection has it's own instance of
    // the object that provides processing of messages into elements
    lazy var tcpMessage = Message()
    lazy var udpMessage = Message()
    
    public var remoteServerAddress: String = ""
    public var remoteServerPort: Int = 0
    var address: String = ""
    
    public var events = DeviceEventTypes()
    
    var deviceName: String = "Unknown Device Name"
    public var displayName: String = ""
    public var serviceName: String = ""
    
    public var isConnected: Bool = false
    public var supportsMotion: Bool = false
    
    private var elements: [Int8: Element] = [:]
    
    init(serviceName: String, displayName: String) {
        self.serviceName = serviceName
        self.displayName = displayName
        deviceName = "Got service device name"
    }
    
    public func send(element: Element) -> Bool {
        switch element.proto {
        case .tcp:
            guard let c = tcpClient else { return false }
            return c.send(element: element)
            
        case .udp:
            if ElementalController.allowUDPService, self is ServerDevice {
                return (self as! ServerDevice).sendUDPElement(element: element)
            } else {
                preconditionFailure("Attempt to send UDP element when UDP disallowed in ElementalController or attempt to send element with server identity.")
            }
        default:
            return false
        }
    }
    
    public func attachElement(_ element: Element) -> Element {
        if !ElementalController.allowUDPService, element.proto == .udp {
            preconditionFailure("Attempt to add UDP element but UDP service disallowed in ElementalController")
        } else {
            elements[element.identifier] = element
            logDebug("\(prefixForLogging(serviceName: serviceName, proto: element.proto)) Element added: \(element.displayName) (\(element.dataType))")
            return element
        }
    }
    
    // Public function that enables a user to obtain a reference
    // to a device specific element based on the element ID.
    public func getElementWith(identifier: Int8) -> Element? {
        guard let element = elements[identifier] else {
            logDebug("\(prefixForLoggingServiceNameUsing(device: self)) Unable to find element for identifier \(identifier)")
            logError("Make sure you're using a matching element collection on both ends of the connection.")
            return nil
        }
        return element
    }
    
    func connectSuccess(proto: Proto) {
        isConnected = true
        logDebug("\(prefixForLoggingServiceNameUsing(device: self)) [\(proto)] Device received connect success")
        
        // Send device name
        let deviceNameElement = attachElement(Element(identifier: SystemElements.deviceName.rawValue, displayName: "Device Name (SYSTEM ELEMENT)", proto: .tcp, dataType: .String))
        deviceNameElement.value = deviceName
        _ = send(element: deviceNameElement)
    }
    
    func connectFailed(proto: Proto) {
        // Clear other connection here
        logDebug("\(prefixForLoggingServiceNameUsing(device: self)) \(proto) connection failed")
        isConnected = false
        events.connectFailed.executeHandler(device: self)
    }
    
    func lostConnection() {
        logDebug("\(prefixForLoggingServiceNameUsing(device: self)) Lost TCP connection to client")
        isConnected = false
        events.deviceDisconnected.executeHandler(device: self)
    }
    
    func processMessageIntoElement(identifier: Int8, valueData: Data) {
        guard let element = getElementWith(identifier: identifier) else { return }
        element.serialize = valueData
        logVerbose("Received element \(element.displayName) with value \(element.value ?? "")")
        // Below zero element identifiers refer to system elements
        if element.identifier >= 0 {
            // DispatchQueue.main.sync {
            element.executeHandlers(element: element, device: self) // User defined
            // }
        } else {
            switch element.identifier {
            case SystemElements.udpIdentifier.rawValue:
                
                // This is received by the client and subsequently included in their
                // UDP messages to uniquely identify their messages as coming from them.
                if element.value is UInt8 { udpIdentifier = element.value as! UInt8 }
                logDebug("\(prefixForLoggingServiceNameUsing(device: self)) Received UDP identififer from \(remoteServerAddress): \(udpIdentifier)")
                
                // Getting the UDP is when we consider things ready to rock and roll
                // from a data transmission standpoint
                
                logDebug("\(prefixForLoggingServiceNameUsing(device: self)) Connected to server.")
                
                events.connected.executeHandler(device: self)
                
            // The client sends the server a device name, which will typically be their
            // hostname.
            case SystemElements.deviceName.rawValue:
                displayName = element.value as! String
                logDebug("\(prefixForLogging(device: self, proto: .tcp)) \(formatDeviceNameForLogging(deviceName: displayName)) device connected from \(address)")
                
            case SystemElements.shutdownMessage.rawValue:
                logDebug("\(prefixForLoggingServiceNameUsing(device: self)) Received shutdown message")
                tcpClient?.shutdown()
                if ElementalController.allowUDPService {
                    guard let u =  (self as! ServerDevice).udpClient else {
                        logError("UDPClient not initialized")
                    }
                    u.shutdown()
                }
            default:
                logError("Received undefined system element")
            }
        }
    }
    
    deinit {
        logDebug("\(prefixForLoggingServiceNameUsing(device: self)) Deinitializing Device")
    }
}

// Service has a collection of these to which it assigns
// UDP IDs
public class ClientDevice: Device {
    var service: Service?
    
    // System elements
    var udpIdentifierElement = Element()
    var deviceNameElement = Element()
    var shutdownMessageElement = Element()
    
    init(service: Service, serviceName: String, displayName: String) {
        super.init(serviceName: serviceName, displayName: displayName)
        self.service = service
        logDebug("\(prefixForLoggingServiceNameUsing(device: self)) Initializing Client Device")
        udpIdentifierElement = attachElement(Element(identifier: SystemElements.udpIdentifier.rawValue, displayName: "UDP identifier (system)", proto: .tcp, dataType: .UInt8))
        deviceNameElement = attachElement(Element(identifier: SystemElements.deviceName.rawValue, displayName: "Device Name (system)", proto: .tcp, dataType: .String))
        shutdownMessageElement = attachElement(Element(identifier: SystemElements.shutdownMessage.rawValue, displayName: "Shutdown Message (system)", proto: .tcp, dataType: .String))
    }
    
    override func lostConnection() {
        super.lostConnection()
        service?.deviceDisconnected(device: self)
    }
}

// Service has two of these, one for TCP and one for UDP
public class ServiceDevice: Device {
    var service: Service?
    
    init(service: Service, serviceName: String, displayName: String) {
        super.init(serviceName: serviceName, displayName: displayName)
        self.service = service
        logDebug("\(prefixForLoggingServiceNameUsing(device: self)) Initializing Service Device")
    }
    
    func serviceFailedToPublish() {
        logDebug("\(prefixForLoggingServiceNameUsing(device: self)) Problem initializing servers")
        // Clear other connection here
        isConnected = false
        events.serviceFailedToPublish.executeHandler(device: self)
    }
}

// Client (Browser) has one of these representing the server
// it is connected to
public class ServerDevice: Device {
    // But only the client side has a UDP client (data flows in one
    // direction with UDP)
    var udpClient: UDPClient?
    
    // System elements
    var udpIdentifierElement = Element()
    var deviceNameElement = Element()
    var shutdownMessageElement = Element()
    
    override init(serviceName: String, displayName: String) {
        super.init(serviceName: serviceName, displayName: displayName)
        logDebug("\(prefixForLoggingServiceNameUsing(device: self)) Initializing Server Device")
        udpIdentifierElement = attachElement(Element(identifier: SystemElements.udpIdentifier.rawValue, displayName: "UDP Identifier (SYSTEM ELEMENT)", proto: .tcp, dataType: .UInt8))
        deviceNameElement = attachElement(Element(identifier: SystemElements.deviceName.rawValue, displayName: "Device Name (SYSTEM ELEMENT)", proto: .tcp, dataType: .String))
        shutdownMessageElement = attachElement(Element(identifier: SystemElements.shutdownMessage.rawValue, displayName: "Shutdown Message (SYSTEM ELEMENT)", proto: .tcp, dataType: .String))
    }
    
    // Used when a client has found a service and wants to connect to it
    public func connect() {
        logDebug("\(prefixForLoggingServiceNameUsing(device: self)) Connecting to service")
        udpClient = UDPClient(device: self, port: remoteServerPort)
        tcpClientConnector = TCPClientConnector(device: self)
        tcpClientConnector?.connectTo(address: remoteServerAddress, port: remoteServerPort)
    }
    
    // Disconnect from service and cleanup
    public func disconnect() {
        logDebug("\(prefixForLoggingServiceNameUsing(device: self)) Disconnecting from service")
        udpClient?.shutdown()
        tcpClient?.shutdown()
        disconnected()  
    }
    
    // When the service goes offline
    public func disconnected() {
        events.deviceDisconnected.executeHandler(device: self)
    }
    
    override func lostConnection() {
        super.lostConnection()
        disconnected()
    }
    
    func sendUDPElement(element: Element) -> Bool {
        if ElementalController.allowUDPService {
            guard let u =  self.udpClient else {
                logError("Attempt to send UDP message without initialized UDP client")
                return false
            }
            return u.sendElement(element: element)
        } else {
            logError("Attempt to send UDP message when UDP is disabled")
        }
    }
}
