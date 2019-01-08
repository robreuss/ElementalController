//
//  UDPService.swift
//  Elemental Controller
//
//  Created by Rob Reuss on 12/7/18.
//  Copyright © 2018 Rob Reuss. All rights reserved.
//

import Foundation
import Socket

class UDPClient {
    
    static var udpProtocolFamily = Socket.ProtocolFamily.inet6
    
    var device: Device?
    
    // Once the socket is open, client needs this to send data
    var remoteAddress: Socket.Address?
    var socket: Socket?
    
    init(device: Device, port: Int) {
        self.device = device
        
        logDebug("\(prefixForLogging(serviceName: device.serviceName, proto: .udp)) Initializing UDP client for ip address \(device.remoteServerAddress) on port \(device.remoteServerPort)")
        
        self.remoteAddress = Socket.createAddress(for: device.remoteServerAddress, on: Int32(port))
        
        do {
            try self.socket = Socket.create(family: UDPClient.udpProtocolFamily, type: Socket.SocketType.datagram, proto: Socket.SocketProtocol.udp)
        }
        catch {
            guard error is Socket.Error else {
                logDebug("\(serviceNameForLogging(device: device)) Error while creating UDP socket: \(error.localizedDescription)")
                return
            }
            logDebug("\(serviceNameForLogging(device: device)) Error fell through: \(error)")
        }
    }
    
    func shutdown() {
        logDebug("\(serviceNameForLogging(device: device)) UDP client shutting down at server request")
        self.socket!.close()
    }
    
    func sendElement(element: Element) -> Bool {
        do {
            if let s = self.socket {
                let _ = try s.write(from: element.encodeAsMessage(udpIdentifier: (device?.udpIdentifier)!), to: self.remoteAddress!)
                return true
            }
            else {
                logDebug("\(serviceNameForLogging(device: self.device)) UDP Attempt to write against nil UDP socket")
                return false
            }
        }
        catch let error {
            guard error is Socket.Error else {
                logDebug("\(serviceNameForLogging(device: self.device)) UDP failure to write element \(element.identifier) to socket with remote address \(String(describing: self.remoteAddress)) with error \(error.localizedDescription)")
                return false
            }
            logDebug("\(serviceNameForLogging(device: self.device)) Fell through: \(error)")
            return false
        }
    }
}

// MARK: -

internal protocol NetworkUDPServerDelegate {
    func receivedElementOverUDP(element: Element)
}

open class UDPService {
    
    var serviceName = "" // For logging purposes
    var socket: Socket?
    var shouldKeepRunning = true
    weak var service: Service? // Delegate
    
    init(service: Service) {
        self.service = service
        self.serviceName = service.serviceName // For convienance
    }
    
    func shutdown() {
        // Only do shutdown procedures if we haven't shutdown already
        // TODO: Should have an event handler here
        if shouldKeepRunning {
            logDebug("\(prefixForLogging(serviceName: serviceName, proto: .udp)) Shutting down UDP Server")
            shouldKeepRunning = false
            socket?.close()
        }
    }

    // Port is passed in based on what port was set or dynamically
    // assigned for TCP.  Both protocols run on the same defined port.
    func listenForConnections(onPort: Int) {

        // TODO: Expose QOS to user
        let queue = DispatchQueue.global(qos: .userInteractive)
        queue.async { [unowned self] in
            
            do {
                
                try self.socket = Socket.create(family: UDPClient.udpProtocolFamily, type: Socket.SocketType.datagram, proto: Socket.SocketProtocol.udp)

                logDebug("\(prefixForLogging(serviceName: self.serviceName, proto: .udp)) UDP service listening on port \(onPort)")
                
                guard let socket = self.socket else {
                logDebug("\(prefixForLogging(serviceName: self.serviceName, proto: .udp)) Unable to unwrap socket")
                  self.shouldKeepRunning = false
                    (DispatchQueue.main).sync {

                        // TODO: Need to callback with this information and probably shut TCP down as well.
                        return
                    }
                    return // Compiler insists on this
                }
                
                // See ElementalController for information about the UDP buffer
                var messageDataBuffer = Data(capacity: ElementalController.UDPBufferSize)
                
                while self.shouldKeepRunning {

                    let (bytesRead, _) = try socket.listen(forMessage: &messageDataBuffer, on: onPort)
                    if bytesRead >= ElementalController.UDPBufferSize {
                        logError("\(prefixForLogging(serviceName: self.serviceName, proto: .udp)) Your UDP messages are exceeding the UDPBufferSize and may not be well-formed.")
                        logError("\(prefixForLogging(serviceName: self.serviceName, proto: .udp)) Send larger messages (particularly those that exceed the UDPBufferSize) via TCP instead.")
                        logError("\(prefixForLogging(serviceName: self.serviceName, proto: .udp)) Use UDP for smaller messages that don't require reliable delivery, such as streams of Doubles representing motion data.")
                    }
                    
                    // Adjust where we look for the UDP ID depending if the header ID is enabled.
                    var udpIdentifierBegins = UDP_ID_BEGINS
                    if !ElementalController.requireHeaderIdentifier { udpIdentifierBegins -= HEADER_ID_LENGTH }
                    
                    // Test to make sure message meets basic requirements
                    if messageDataBuffer.count < udpIdentifierBegins + UDP_ID_LENGTH {
                        logError("\(prefixForLogging(serviceName: self.serviceName, proto: .udp)) Received malformed element message.  Clearing buffer.")
                        messageDataBuffer = Data(capacity: ElementalController.UDPBufferSize)
                    } else {
                        
                        while messageDataBuffer.count > 0 && self.shouldKeepRunning  {
                        
                            // Get the UDP identifier so we know what client device is connecting
                            let udpIdentifierData = messageDataBuffer.subdata(in: udpIdentifierBegins..<udpIdentifierBegins + UDP_ID_LENGTH)
                            let udpIdentifier = UInt8(Element.uint8Value(data: udpIdentifierData))
                            
                            // Get the device that's sending data, presumably
                            let device = self.service!.getDeviceForUDPIdentififer(udpIdentifier: udpIdentifier)
                            if device == nil {
                                logError("\(prefixForLogging(serviceName: self.serviceName, proto: .udp)) Unable to find device for processing UDP message.")
                            } else {
                                // Extract the identifier and value data from the message
                                let (identifier, _, valueData, remainingData) = device!.udpMessage.process(data: messageDataBuffer,  proto: Proto.udp, device: device!)  // Extract identifier and value from the raw Data
                                messageDataBuffer = remainingData
                                if identifier == MALFORMED_MESSAGE_IDENTIFIER {
                                    break
                                } else if identifier == MORE_COMING_IDENTIFIER {  // In the case of UDP, we don't buffer so we just grap the next batch of data
                                    break
                                } else {
                                    // Process the identity and value of the element, and in turn, call handlers
                                    // Execution won't be put back on the main thread until the handlers are called
                                    device!.processMessageIntoElement(identifier: identifier, valueData: valueData)
                                }
                            }
                        }
                    }

                }
                
                // Probably shutdown was already called and continueRunning set to false, but we
                // call shutdown anyway.
                self.shutdown()
                
            } catch let error {
                guard error is Socket.Error else {
                    logDebug("\(prefixForLogging(serviceName: self.serviceName, proto: .udp)) UDP server stopped on error: \(error.localizedDescription)")
                    (DispatchQueue.main).sync {
                        return
                    }
                    return  // TODO: Add throw here to silence compiler warning when this is absent
                }
            }
        }
    }
    
    deinit {
        logDebug("\(prefixForLogging(serviceName: serviceName, proto: .udp))UDP Server deinitialized")
    }
    
}
