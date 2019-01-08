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
    var parentService: Service?
    var listenerSocket: Socket?
    var isListening: Bool = false
    var continueRunning = true
    let socketLockQueue = DispatchQueue(label: "net.simplyformed.socketLockQueue")
    
    init(parentServer: Service) {
        parentService = parentServer
        logDebug("\(prefixForLogging(serviceName: (parentService?.serviceName)!, proto: .tcp)) Initializing TCPServer")
    }
    
    deinit {
        logDebug("\(prefixForLogging(serviceName: (parentService?.serviceName)!, proto: .tcp)) Deinit TCPServer, closing socket")
        self.listenerSocket?.close()
    }
    
    func listenForConnections(onPort: Int) {
        let queue = DispatchQueue.global(qos: .userInteractive)
        
        queue.async {
            do {
                // Create an IPV6 socket...
                try self.listenerSocket = Socket.create(family: .inet)
                guard let socket = self.listenerSocket else {
                    logDebug("\(prefixForLogging(serviceName: (self.parentService?.serviceName)!, proto: .tcp)) Unable to unwrap socket...")
                    (DispatchQueue.main).sync {
                        return
                    }
                    return
                }
                
                try socket.listen(on: onPort)
                
                self.isListening = true
                
                //logDebug("*************************************************************************")
                logDebug("\(prefixForLogging(serviceName: self.parentService!.serviceName, proto: .tcp)) TCP service listening on port \(socket.listeningPort)")
                //logDebug("*************************************************************************")
                
                self.parentService!.publishTCPServiceAdvertisment(onPort: Int(socket.listeningPort))
                self.parentService!.startUDPService(onPort: Int(socket.listeningPort))
                
                repeat {
                    let newSocket = try socket.acceptClientConnection()
                    
                    self.parentService!.clientDeviceConnectedOn(socket: newSocket)

                    
                } while self.continueRunning
                
            } catch let error {
                guard let socketError = error as? Socket.Error else { logDebug("\(prefixForLogging(serviceName: (self.parentService?.serviceName)!, proto: .tcp)) TCPServer: Unexpected error...")
                    self.isListening = false
                    (DispatchQueue.main).sync {
                        return
                    }
                    return
                }
                
                if self.continueRunning {
                    logDebug("\(prefixForLogging(serviceName: (self.parentService?.serviceName)!, proto: .tcp)) TCPServer: Error reported: \(socketError.description)")
                    self.isListening = false
                }
            }
        }
    }
    
    func shutdown() {
        logDebug("\(prefixForLogging(serviceName: (parentService?.serviceName)!, proto: .tcp)) Shutting down TCP server listener")
        continueRunning = false
        listenerSocket!.close()
    }
}

// MARK: -

class TCPClient {
    var device: Device
    var socket: Socket?
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
    
    func send(element: Element) -> Bool {
        if connected == false {
            logDebug("\(prefixForLoggingDevice(device: device)) Ignoring send element request because have no connection")
            logDebug("\(prefixForLoggingDevice(device: device)) Shutting down TCP client")
            shouldKeepRunning = false
            socket!.close()
            connected = false
            return false
        }
        do {
            /* Removed this - it needs to be updated for read/write elements
            // TODO: Check for nil socket and socket.connected
            guard let value = element.value else {
                logError("\(prefixForLoggingDevice(device: device)) Encountered nil value attempting to send element: \(element.displayName)")
                return false
            }
 */
            //logVerbose("\(prefixForLoggingDevice(device: device)) Sending element message: \(element.encodeAsMessage) over \(element.proto) with value: \(String(describing: element.value))")
            try socket!.write(from: element.encodeAsMessage(udpIdentifier: (device.udpIdentifier)))
            return true
        }
        catch let error {
            logError("\(prefixForLoggingDevice(device: device)) TCP send failure: \(error)")
            self.connected = false
            logError("\(prefixForLoggingDevice(device: device)) Remote TCP service seems to have stopped unexpectedly")
            disconnected()
            return false
        }
    }

    func disconnected() {
        if device is ServerDevice {
            (device as! ServerDevice).disconnected()
        } else {
            device.lostConnection(proto: .tcp)
        }
    }
    
    func shutdown() {
        logDebug("\(prefixForLoggingDevice(device: device)) Shutting down TCP service")
        self.shouldKeepRunning = false
        socket!.close()
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
                    let bytesRead = try socket!.read(into: &readData)
                    
                    // TODO: Clear elementDataBuffer on disconnect?
                    // self.elementDataBufferLockQueue.sync {
                    messageDataBuffer.append(readData)
                    
                    while messageDataBuffer.count > 0 && self.shouldKeepRunning {
                        let (identifier, udpIdentifier, valueData, remainingData) = device.tcpMessage.process(data: messageDataBuffer,  proto: .tcp, device: device)
                        messageDataBuffer = remainingData
                        if identifier == MALFORMED_MESSAGE_IDENTIFIER {
                            break
                        } else if identifier == MORE_COMING_IDENTIFIER {
                            break
                        } else {
                            device.processMessageIntoElement(identifier: identifier, valueData: valueData)

                        }
                    }

                    // If there's anything left in the buffer after a disconnect, finish
                    // processing it
                    if bytesRead == 0 {
                        logDebug("\(prefixForLoggingDevice(device: device)) Got disconnect.  Processing buffer (\(messageDataBuffer.count)).")
                        if messageDataBuffer.count == 0 {
                            logDebug("\(prefixForLoggingDevice(device: device)) Buffer clear.")
                            self.disconnected()
                            self.shouldKeepRunning = false
                        }
                    }
                    
                    readData.count = 0
                }  while self.shouldKeepRunning

            }
            catch let error {
                guard let socketError = error as? Socket.Error else {
                    logDebug("\(prefixForLoggingDevice(device: device)) Unexpected error by connection at \(socket!.remoteHostname):\(socket!.remotePort)")
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
    func lostConnection(proto: Proto)
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
    
    func send(element: Element) {
        _ = connection?.send(element: element)
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
                    self.socket = try Socket.create(family: UDPClient.udpProtocolFamily)
                }
                catch let error {
                    logError("\(serviceNameForLogging(device: self.device)) TCP Client got error creating socket: \(error)")
                    self.socket?.close()
                    DispatchQueue.main.sync {
                        self.delegate?.connectFailed(proto: .tcp)
                    }
                    return
                }
                
                logDebug("\(serviceNameForLogging(device: self.device)) Connecting to server at \(address) \(port)")
                try self.socket!.connect(to: address, port: Int32(port))
                
                // TODO: Pass socket back to delegate
                self.device!.tcpClient = TCPClient(device: self.device!, socket: self.socket!)
                self.device!.tcpClient!.run()
                if Thread.isMainThread {
                        self.device?.connectSuccess(proto: .tcp)
                } else {
                    (DispatchQueue.main).sync {
                        self.device?.connectSuccess(proto: .tcp)
                    }
                }
            }
            catch let error {
                logError("\(serviceNameForLogging(device: self.device)) TCP Client got error connecting socket: \(error)")
                DispatchQueue.main.sync {
                    self.delegate?.connectFailed(proto: .tcp)
                }
            }
            
            if self.socket!.isConnected {
                logDebug("\(serviceNameForLogging(device: self.device)) TCP Client connected to \(address)")
                self.connection?.connected = true
            }
        }
    }
}
