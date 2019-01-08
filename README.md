***This is alpha software and should be utilized at your own risk.  The programmatic interface is subject to change.***
# Elemental Controller

Intended for Swift developers, this framework impliements a simple application layer protocol above TCP and UDP to provide a lean, low latency, and event-driven approach to controlling devices in a LAN-based environment.  It is designed for use cases such as controlling a Raspberry Pi robot on a LAN rather than managing a large fleet of agricultural sensors across the world.

It runs on iOS, MacOS, tvOS and Linux.

Conceptually, the framework is built up around the notion of a set of type-specific control "elements" which are defined at compile time. A reference ID and element definition common to both endpoints provides the basis for the exchange of element data, within a tiny message envelope.  At the end-point, a message is decoded and a handler block triggered by the event. 

An alternative to utilizing raw TCP or UDP, it offers:

* Easy service publishing and discovery
* Easy making of and managing connections
* A lightweight message protocol
* Application-level event-driven model
* Strongly-typed approach

Compared to MQTT:

* Less complexity, no broker
* Architectural simplicity of request/response versus pub/sub
* Low latency is supportive of "firm" real-time implementations
* Tight coupling for uses that require that
* Single codebase for client and server
* Bias toward performance over scalability
* No security yet, coming soon (SSL/TLS)

### Features:
* Support for iOS, tvOS, macOS and Linux, written in Swift 4.1
* Support for the selective use of TCP or UDP per element
* Tested on the Raspberry Pi and Raspberry Pi Zero
* Event-oriented handling of incoming elements (block-based)  
* Dynamic or static port assignment with Zeroconf service discovery
* Minimal latency 
* Flexible model that allows a single instance to be both a client and server, supporting a variety of network topologies including relays and P2P.
### Latency
During informal testing, latency was measured by sending a Unix timestamp (64 bits) as a  payload from an iOS device (client) to a Raspberry Pi 3 Model B (server) over TCP and measuring the elapsed time for a round trip.  On my home WiFi, sending 90 messages/second, latency was typically about 10ms for the round trip when averaged over 20,000 messages.  That was equivilent to the ping response times tested during the same session, suggesting little or no overhead beyond underlying network performance.
### Throughput
During informal testing, throughput was measured by sending a 64-bit element message every 1/10th of a millisecond.  Transmission occured from an iPhone X to a Raspberry Pi 3 Model B and approximately 3500 messages/second were processed inclusive of event handling.
### Message Envelope
Messages sent over TCP have a message envelope of 5 bytes which precede the value data, which is of variable length depending on data type.  UDP message envelopes are 6 bytes to accomodate a UDP device identifier, required to identify clients given the connectionless state of a UDP service.
  
* **_1 Byte_**: An element identifier that refers to a data structure shared by both end points, containing the element display name, type and network protocol (TCP or UDP).  
* **_4 bytes_**: An integer indicating the length in bytes of the value of the element.
* **_1 byte_**: UDP device identifier, an integer that identifies the device that has sent a UDP message.  _Only used with UDP data._
* **_Variable_**: The data value itself, which could be a fixed length, in the case of integers, Float or Double, or variable in the case of a String or Data element.
## TCP and UDP Support
When an Elemental Controller service is setup, both a TCP and UDP service are established on the same port, which could be a static port you set or a port dynamically allocated by the OS (by specifying a port of "0").  Establishing these dual channels is handled automatically. A setting is available to disable UDP if you wish.  

TCP is a connection-oriented protocol and therefore supports bi-directional communication, whereas UDP only supports communication from the client to the server.  

Each individual element has a prototype property, either TCP and UDP. You can mix and match protocols on the elements that compose your set on the basis of whether you need reliability (TCP) or performance (UDP) per element.  You should prefer TCP if you need to transfer larger messages, such as files, whereas UDP is more appropriate to streaming large numbers of small messages quickly.    


## Installation 
### CocoaPods
Coming soon.  For now use Carthage for iOS/macOS/tvOS, or just close the project and add the files.
### Carthage
Learn about [Carthage](https://github.com/Carthage/Carthage).

Using a Cartfile, you can get the ElementalController framework for iOS, tvOS, and macOS, without needing to worry about it's dependency on [BlueSocket](https://github.com/IBM-Swift/BlueSocket).  Here's what you need to add to your Cartfile:

`github "robreuss/ElementalController" ~> 0.0.4`

One you run the command `carthage update` you'll fine the frameworks available in your project folder under "Carthage/Build".  You should only need to add ElementalController by dragging it from there to the Embedded Binaries section of your target, but not BlueSocket.

### Swift Package Manager
A Package.swift file is provided in the respository and usage is typical of SPM.  On Linux, it will add both [BlueSocket](https://github.com/IBM-Swift/BlueSocket) and [NetService](https://github.com/Bouke/NetService).  

## Usage
### Client-Side 
Here's an example of setting up the framework with a few elements on the client side.  This is not a complete representation of available functionality.  Note that Linux hosts cannot at this point act as a client (browsing for services), only servers (publishing services).  This is a temporary limitation of the zero config package used and should be solved shortly.

Counter-intuitively, elements and their handlers are defined first, and the command to connect follows that.

```swift
import ElementalController

// Define a integer identifier for elements
enum ElementIdentifier: Int8 {
    
    case brightness = 1
    case backlight = 2
    
    var description: String {
    	switch self {
    	case .brightness: return "Brightness"
    	case .backlight: return "Backlight"
    	}
    }
}
    
var elementalController = ElementalController()
elementalController.setupForBrowsingAs(deviceNamed: "Rob's iPhone")
    
// Before starting to browse, setup handlers...
elementalController.browser.events.onFoundServer.handler { serverDevice in
    
    // Attach elements to server...
    let brightness = serverDevice.attachElement(
        Element(identifier: ElementIdentifier.brightness.rawValue,
                displayName: "Brightness",
                proto: .tcp,
                dataType: .Float))
    
    let backlight = serverDevice.attachElement(
        Element(identifier: ElementIdentifier.backlight.rawValue,
                displayName: "Backlight",
                proto: .tcp,
                dataType: .Float))
    
    // Once connected, you can send elements to the server...
    serverDevice.events.onConnect.handler = {serverDevice in
        
        if let brightness = serverDevice.getElementWith(identifier: ElementIdentifier.brightness.rawValue) {
            brightness.value = 0.0
            let sendSuccess = serverDevice.send(element: brightness)
        } else {
            logError("Unable to find brightness element")
        }
    }
    
    // Finally, connect to the server!
    serverDevice.connect()
}
    
// Start browsing for the service...
elementalController.browser.browse(serviceName: "screen_control")

```
### Server-Side 
Code for the server side follows a similar pattern as the client side, with element and handler definition first and publishing only once those are done:
```swift
import ElementalController

// Element identifiers must be the same as the client side
enum ElementIdentifier: Int8 {
    
    case brightness = 1
    case backlight = 2
    
    var description: String {
        switch self {
        case .brightness: return "Brightness"
        case .backlight: return "Backlight"
        }
    }
}
    
var elementalController = ElementalController()
elementalController.setupForService(serviceName: "screen_control", displayName: "My server")
    
elementalController.service.events.onDeviceConnected.addHandler(
    handler: { _, device in
        
        // Attach elements to client device...
        let brightness = device.attachElement(
            Element(identifier: ElementIdentifier.brightness.rawValue,
                    displayName: "Brightness",
                    proto: .tcp,
                    dataType: .Float))
        
        let backlight = device.attachElement(
            Element(identifier: ElementIdentifier.backlight.rawValue,
                    displayName: "Backlight",
                    proto: .tcp,
                    dataType: .Float))
    
	    brightness.handler = { element, _ in
	        logDebug("Server received a brightness element: \(element.value)")
	    }
	    
	    backlight.handler = { element, _ in
	    	logDebug("Server received a backlight element: \(element.value)")
	    }
    
})
    
// Setting this to port "0" will automatically select an available port
elementalController.service.publish(onPort: 0)
```
## Thanks
ElementalController is really just glue around the following two projects:
### NetService
Linux-side Zeroconf functionality (publishing and browsing of services) is thanks to [NetService](https://github.com/Bouke) by [Bouke Haarsma](https://github.com/Bouke).  
### BlueSocket
TCP and UDP functionality is thanks to [BlueSocket](https://github.com/IBM-Swift/BlueSocket).





