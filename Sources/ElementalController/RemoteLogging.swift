import Foundation

var eid_logger: Int8 = 0

public struct LogLine: Codable {
    public var text = ""
    public var logLevel: LogLevel
}

public class RemoteLogging {
    
    var elementalController = ElementalController()
    var serverDevice: ServerDevice?
    var clientDevice: Device?
    var serviceName: String = ""
    var element: Element?
    var isConnected: Bool = false
    
    public typealias LogLineHandler = ((LogLine) -> Void)
    public var incomingLogLineHandler: LogLineHandler?

    public init() {}
    
    public func setupAsServer(serviceName: String, deviceName: String) {
        
        elementalController.setupForService(serviceName: serviceName, displayName: deviceName)
        
        elementalController.service.events.deviceDisconnected.handler =  { _, _ in
            
            self.isConnected = false
            
        }
        
        elementalController.service.events.deviceConnected.handler =
            { _, device in
                
                self.isConnected = true

                let element = device.attachElement(Element(identifier: eid_logger, displayName: "Logger", proto: .tcp, dataType: .Data))

                element.handler = {  element, device in
                    
                    let jsonDecoder = JSONDecoder()
                    
                    do {
                        if let logLine = element.dataValue {
                            let decodedLogLine = try jsonDecoder.decode(LogLine.self, from: logLine)
                            if let handler = self.incomingLogLineHandler {
                                
                                handler(decodedLogLine)
                                
                            }
                            
                        } else {
                            // TODO: Error
                        }
                    }
                    catch {
                        //self.errorManager.sendError(message: "JSON decoding error on element \(element.displayName): \(error)")
                    }
                    
                }
            }

        do {
            try elementalController.service.publish(onPort: 0)
        } catch {
            logDebug("Could not publish: \(error)")
        }

    }

    public func setupAsClient(serviceName: String, deviceName: String) {
        
        self.serviceName = serviceName
        
        elementalController.setupForBrowsingAs(deviceNamed: deviceName)
        
        // MARK: -
        // MARK: Handlers
        
        elementalController.browser.events.foundServer.handler { serverDevice in
            
            print("FOUND SERVER")
            
            self.serverDevice = serverDevice
            
            self.element = serverDevice.attachElement(Element(identifier: eid_logger, displayName: "Logger", proto: .tcp, dataType: .Data))

            /*
            self.element.handler = { element, _ in

                guard let logger = element.data else { return }
                self.telemetryRPM.text = "RPM: \(rpmRounded)"
                
            }
             */
  
            //self.statusBar.text = "Connecting..."
            
            serverDevice.events.connected.handler = { _ in
                print("CONNECTED TO SERVICE")
                self.isConnected = true
            }
            
            serverDevice.events.deviceDisconnected.handler = { _ in
                self.isConnected = false
                print("DISCONNECTED FROM SERVICE")
                //self.statusBar.text = "Searching for \(self.roverMotorsServiceName)..."
                sleep(5) // Don't rush or we might get a reconnect to a disappearing server
                self.elementalController.browser.browseFor(serviceName: self.serviceName)
            }
            
            serverDevice.connect()

        }
        
        //self.statusBar.text = "Searching for service \(serviceName)..."
        elementalController.browser.browseFor(serviceName: serviceName)
       
      
    }
    
    public func sendLogLineToServer(logLine: LogLine) {

        if !self.isConnected { return }
        
        let jsonEncoder = JSONEncoder()
        do {
            let jsonData = try jsonEncoder.encode(logLine)
            if let e = element {
                e.dataValue = jsonData
                do {
                    if let sd = self.serverDevice {
                        try sd.send(element: e)
                    }
                }
                catch {
                    //errorManager.sendError(message: "Sending element \(elementHeadingData.displayName) resulted in error: \(error)")
                }
            }
        }
        catch {
            print("Got JSON encoding error: \(error)")
        }
    }
}


