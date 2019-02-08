//
//  TCPClient.swift
//  ElementalController
//
//  Created by Rob Reuss on 12/10/18.
//  Copyright © 2019 Rob Reuss. All rights reserved.
//

import Foundation
import Socket

class TCPService {
    var parentService: Service
    var listenerSocket: Socket?
    var isListening: Bool = false
    var continueRunning = true
    let socketLockQueue = DispatchQueue(label: "net.simplyformed.socketLockQueue")
    
    init(parentServer: Service) {
        parentService = parentServer
        logDebug("\(prefixForLogging(serviceName: parentService.serviceName, proto: .tcp)) Initializing TCPServer")
    }
    
    deinit {
        logDebug("\(prefixForLogging(serviceName: parentService.serviceName, proto: .tcp)) Deinit TCPServer, closing socket")
        
        listenerSocket?.close()
    }
    
    func listenForConnections(onPort: Int) throws {
        let queue = DispatchQueue.global(qos: .userInteractive)
        
        queue.async {
            do {
                // Create a socket...
                logVerbose("Setting up IPv6 socket")
                try self.listenerSocket = Socket.create(family: ElementalController.protocolFamily)
                guard let socket = self.listenerSocket else {
                    logDebug("\(prefixForLogging(serviceName: self.parentService.serviceName, proto: .tcp)) Unable to unwrap socket...")
                    (DispatchQueue.main).sync {
                        return
                    }
                    return
                }
                
                try socket.listen(on: onPort)
                
                self.isListening = true
                
                //logDebug("*************************************************************************")
                logDebug("\(prefixForLogging(serviceName: self.parentService.serviceName, proto: .tcp)) TCP service listening on port \(socket.listeningPort)")
                //logDebug("*************************************************************************")

                try self.parentService.startUDPService(onPort: Int(socket.listeningPort))
                sleep(1) // Give UDP a second to startup before we advertise
                self.parentService.publishTCPServiceAdvertisment(onPort: Int(socket.listeningPort))

                
                repeat {

                    do {
                        let newSocket = try socket.acceptClientConnection()
                        try self.parentService.clientDeviceConnectedOn(socket: newSocket)
                    }
                    catch {
                        logDebug("\(prefixForLogging(serviceName: self.parentService.serviceName, proto: .tcp)) Failure accepting client connection: \(error)")
                    }

                    
                } while self.continueRunning
                
            } catch {
                guard let socketError = error as? Socket.Error else { logDebug("\(prefixForLogging(serviceName: self.parentService.serviceName, proto: .tcp)) TCPServer: Unexpected error...")
                    self.isListening = false
                    (DispatchQueue.main).sync {
                        return
                    }
                    return
                }
                
                if self.continueRunning {
                    logDebug("\(prefixForLogging(serviceName: self.parentService.serviceName, proto: .tcp)) TCPServer: Error reported: \(socketError.description)")
                    self.isListening = false
                }
            }
        }
    }
    
    func shutdown() {
        logDebug("\(prefixForLogging(serviceName: parentService.serviceName, proto: .tcp)) Shutting down TCP server listener")
        continueRunning = false
        if let ls = listenerSocket {
            ls.close()
        } else {
            logError("\(prefixForLogging(serviceName: parentService.serviceName, proto: .tcp)) Nil listenerSocket, unable to close")
        }

    }
}

// MARK: -

class TCPClient {
    var device: Device
    var socket: Socket
    var connected = false
    var message: Message?
    let elementDataBufferLockQueue = DispatchQueue(label: "elementDataBufferLockQueue")
    var shouldKeepRunning = true

    init(device: Device, socket: Socket) {
        self.device = device
        connected = true
        self.socket = socket
        message = Message()
    }
    
    deinit {
        logDebug("\(prefixForLoggingDevice(device: device)) TCP server shutdown")
    }
    
    func send(element: Element) throws {
        if connected == false {
            logDebug("\(prefixForLoggingDevice(device: device)) Ignoring send element request because have no connection")
            throw ElementSendError.attemptToSendNoConnection
        }
        do {
            /* Removed this - it needs to be updated for read/write elements
            // TODO: Check for nil socket and socket.connected
            guard let value = element.value else {
                logError("\(prefixForLoggingDevice(device: device)) Encountered nil value attempting to send element: \(element.displayName)")
                return false
            }
 */
            //logDebug("\(prefixForLoggingDevice(device: device)) Sending element message: \(element.encodeAsMessage) over \(element.proto) with value: \(String(describing: element.value))")
            try socket.write(from: element.encodeAsMessage(udpIdentifier: (device.udpIdentifier)))
        } catch {
            logError("\(prefixForLoggingDevice(device: device)) TCP send failure: \(error)")
            disconnect()
        }
    }   
    
    // TODO: Consolidate the naming of these methods
    func disconnect() {
        if connected {
            socket.close()
            connected = false
            shouldKeepRunning = false
            if device is ServerDevice {
                (device as! ServerDevice).disconnected()
            } else {
                device.lostConnection()
            }
        }
    }
    
    func shutdown() {
        logDebug("\(prefixForLoggingDevice(device: device)) Shutting down TCP service")
        shouldKeepRunning = false
        socket.close()
        connected = false
    }
    
    func run() {
        // Get the global concurrent queue...
        let queue = DispatchQueue.global(qos: .userInteractive)
        
        // Create the run loop work item and dispatch to the default priority global queue...
        queue.async { [unowned self, socket] in
            
            let device = self.device
            var messageDataBuffer = Data()
            var readData = Data(capacity: ElementalController.TCPBufferSize)

            do {
                repeat {
                    let bytesRead = try socket.read(into: &readData)
                    messageDataBuffer.append(readData)
                    
                    while messageDataBuffer.count > 0 && self.shouldKeepRunning {
                        let (identifier, _, valueData, remainingData) = device.tcpMessage.process(data: messageDataBuffer, proto: .tcp, device: device)
                        messageDataBuffer = remainingData
                        if identifier == MALFORMED_MESSAGE_IDENTIFIER {
                            break
                        } else if identifier == MORE_COMING_IDENTIFIER {
                            // We may be caught in a large message we'll never get the rest of, so just exit regardless
                            // of buffered data
                            if bytesRead == 0 {
                                messageDataBuffer = Data()
                                self.shouldKeepRunning = false
                            }
                            break
                        } else {  // TODO: Add constant for no identifier (because TCP) here
                            device.processMessageIntoElement(identifier: identifier, valueData: valueData)
                        }
                    }
                    
                    // If there's anything left in the buffer after a disconnect, finish
                    // processing it
                    if bytesRead == 0 {
                        logDebug("\(prefixForLoggingDevice(device: device)) Got disconnect.  Processing buffer (\(messageDataBuffer.count)).  Should keep running: \(self.shouldKeepRunning)")
                        if messageDataBuffer.count == 0 {
                            logDebug("\(prefixForLoggingDevice(device: device)) Buffer clear.")
                            self.disconnect()
                        }
                    }
                    
                    readData.count = 0
                } while self.shouldKeepRunning
            } catch {
                guard let socketError = error as? Socket.Error else {
                    logDebug("\(prefixForLoggingDevice(device: device)) Unexpected error by connection at \(socket.remoteHostname):\(socket.remotePort)")
                    self.connected = false
                    (DispatchQueue.main).sync {
                        return
                    }
                    return
                }
            }
        }
    }
}

// MARK: -

protocol TCPClientConnectorDelegate {
    func connectSuccess(proto: Proto)
    func lostConnection()
    func connectFailed(proto: Proto)
    var tcpClient: TCPClient? { get set }
}

class TCPClientConnector {
    static let bufferSize = 4096
    
    var device: ServerDevice?
    var continueRunning = true
    var socket: Socket?
    let socketLockQueue = DispatchQueue(label: "net.simplyformed.socketLockQueue")
    var delegate: TCPClientConnectorDelegate?
    var connection: TCPClient?
    
    init(device: ServerDevice) {
        self.device = device
    }
    
    deinit {
        logDebug("TCP Client deinit")
    }
    
    func send(element: Element) throws {
        try connection?.send(element: element)
    }
    
    var connected: Bool {
        guard let c = connection else {
            logDebug("\(serviceNameForLogging(device: device)) Testing connection for nil, so no connection")
            return false
        }
        return (c.connected)
    }
    
    func connectTo(address: String, port: Int) {
        let queue = DispatchQueue.global(qos: .userInteractive)
        
        queue.async { [self] in
            
            do {
                do {
                    self.socket = try Socket.create(family: ElementalController.protocolFamily)
                } catch {
                    logError("\(serviceNameForLogging(device: self.device)) TCP Client got error creating socket: \(error)")
                    self.socket?.close()
                    DispatchQueue.main.sync {
                        self.delegate?.connectFailed(proto: .tcp)
                    }
                    return
                }
                
                logDebug("\(prefixForLogging(device: self.device, proto: .tcp)) Connecting to server at \(address) \(port)")
                try self.socket!.connect(to: address, port: Int32(port))
                
                // TODO: Pass socket back to delegate
                self.device!.tcpClient = TCPClient(device: self.device!, socket: self.socket!)
                self.device!.tcpClient!.run()
                if Thread.isMainThread {
                    try self.device?.connectSuccess(proto: .tcp)
                } else {
                    try (DispatchQueue.main).sync {
                        try self.device?.connectSuccess(proto: .tcp)
                    }
                }
            } catch {
                // TODO: Should this be calling back to delegate or device?
                logError("\(serviceNameForLogging(device: self.device)) TCP Client got error connecting socket: \(error)")
                if Thread.isMainThread {
                    self.delegate?.connectFailed(proto: .tcp)
                } else {
                    (DispatchQueue.main).sync {
                    self.delegate?.connectFailed(proto: .tcp)
                    }
                }
            }
            
            if self.socket!.isConnected {
                logDebug("\(prefixForLogging(device: self.device, proto: .tcp)) Client connected to \(address)")
                self.connection?.connected = true
            }
        }
    }
}
