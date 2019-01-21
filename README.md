# Elemental Controller
> **_This software is in active development and should be considered at an alpha stage.  Use with care and anticipate changes._**

Intended for Swift developers, this framework implements a simple application layer protocol over TCP and UDP to provide a lean, low latency, and event-driven approach to controlling devices in a LAN-based environment.  It is designed for use cases such as controlling a Raspberry Pi robot on a LAN rather than managing a large fleet of agricultural sensors across the world.  

It runs on iOS, MacOS, tvOS and Linux.

Conceptually, the framework is built up around the notion of a set of type-specific control "elements" which are defined at compile time. A reference ID and element definition common to both endpoints provides the basis for the exchange of element data, within a tiny message envelope.  At the end-point, a message is decoded and a handler block triggered by the event. This occurs over TCP and UDP services that are managed by the framework.

It is a single codebase for both client and server.

An alternative to utilizing raw TCP or UDP, it offers:

* Easy service publishing and discovery
* Easy making of and managing connections
* A lightweight message protocol
* Application-level event-driven model
* Strongly-typed approach

## Features
* Works on iOS, tvOS, macOS and Linux (tvOS not tested yet)
* Tested on Ubuntu, Ubuntu Mate and Raspberian
* Tested on the Raspberry Pi and Raspberry Pi Zero
* Any instance can be a client or server or both, enabling a variety of network topologies
* Any instance can connect to or publish multiple services
* Support for the selective use of TCP or UDP per element
* Performance benefits of UDP for certain applications
* Open, persistent, bi-drectional connections using TCP
* Event-oriented handling of incoming elements (block-based)  
* Dynamic or static port assignment with Zeroconf service discovery

## Limitations (esp. compared to MQTT and HTTP/WebSockets)
* More focused on LAN than on WAN or Internet 
* Not really designed with low power in mind
* Different approach to QoS than pub/sub approach (MQTT)
* No security yet (coming soon, SSL/TLS)
* Lacks industry standardization and focused instead on Swift, Linux and iOS integrations

## Use cases
### Sensors
Any simple sensor-based application where you want to send information from a Raspberry Pi to another Linux device/machine or to an iOS device.  For example, a set of atmospheric sensors can be easily intefaced with by defining an element for each data source (temp, humidity, barometric pressure), and setting up timers to send the data.  ElementalController makes it easy to set up the services, channels and client to make something like that work quickly, in a few lines of code.
### Robotics
Controlling a robot that has a Raspberry Pi on-board using an iPhone.  Motion data can be sent from the iPhone at it's highest sampling rates (~100 Hz), providing precision control.  And accelerometer data from the Pi can be sent back to the phone based on the robot's motion, along with proximity sensing data, collision-detection and imaging data.  
### Sound Synthesis
The iPhone or iPad can make an excellent input device for a sound synthesizer project where it is critical to minimize latency and maximize throughput when using motion data or rapid-motion touch at 120 Hz to generate and shape sound.  The ease with which elements can be setup make it trivial to define a large number of controls and to write block-based code to implement the element-specific functionality on the receiving end.
### Coordinating an Array or Cluster
It's easy to setup multiple services or handle connections from multiple clients, so in scenarios where a set of Raspberry Pi's are used in a simple array or cluster, the framework can be a useful tool to control nodes and receive status information from them.

## Sample Apps
[iOS](https://github.com/robreuss/ElementalController_iOS_Sample) and [Linux / macOS](https://github.com/robreuss/ElementalController_Linux_Sample) sample applications are available to be used as a pair in demonstrating client-server interaction and the basic workflow of ElementalController. 
## Details
### Latency
During informal testing, latency was measured by sending a Unix timestamp (64 bits) as a  payload from an iOS device (client) to a Raspberry Pi 3 Model B (server) over TCP and measuring the elapsed time for a round trip.  On my home WiFi, sending 90 messages/second, latency was typically about 15ms for the round trip when averaged over 20,000 messages.  That was equivilent to the ping response times tested during the same session, suggesting little or no overhead beyond underlying network performance.
### Throughput
During informal testing, throughput was measured by sending a 64-bit element message every 1/10th of a millisecond.  Transmission occured from an iPhone X to a Raspberry Pi 3 Model B and approximately 3500 messages/second were processed inclusive of event handling.
### Message Envelope
Messages sent over TCP have a message envelope of 5 bytes which precede the value data, which is of variable length depending on data type.  UDP message envelopes are 6 bytes to accomodate a UDP device identifier, required to identify clients given the connectionless state of a UDP service.
  
* **_1 Byte_**: An element identifier that refers to a data structure shared by both end points, containing the element display name, type and network protocol (TCP or UDP).  
* **_4 bytes_**: An integer indicating the length in bytes of the value of the element.
* **_1 byte_**: UDP device identifier, an integer that identifies the device that has sent a UDP message.  _Only used with UDP data._
* **_Variable_**: The data value itself, which could be a fixed length, in the case of integers, Float or Double, or variable in the case of a String or Data element.
### TCP and UDP Support
When an Elemental Controller service is setup, both a TCP and UDP service are established on the same port, which could be a static port you set or a port dynamically allocated by the OS (by specifying a port of "0").  Establishing these dual channels is handled automatically. A setting is available to disable UDP if you wish.  

Since TCP is a connection-oriented protocol, whereas UDP only supports communication from the client to the server, it supports bi-directional communication, while UDP is unidirectional.  

Each individual element has a prototype property, either TCP and UDP. You can mix and match protocols on the elements that compose your set on the basis of whether you need reliability (TCP) or performance (UDP) per element.  You should prefer TCP if you need to transfer larger messages, such as files, whereas UDP is more appropriate to streaming large numbers of small messages quickly.    
## Installation 
### On Linux and macOS
#### Swift Package Manager
A `Package.swift` file is provided in the respository and usage is typical of SPM.  On Linux, it will add both [BlueSocket](https://github.com/IBM-Swift/BlueSocket) and [NetService](https://github.com/Bouke/NetService).  Your Swift `Package.swift` would look something like this:
```swift
// swift-tools-version:4.1
import PackageDescription

let package = Package(
    name: "EC_ElementTests",
    dependencies: [
        .package(url: "https://github.com/robreuss/ElementalController.git", .branch("develop")),
    ],
    targets: [
        .target(
            name: "EC_ElementTests",
            dependencies: ["ElementalController"]),
    ]
)
```

#### Server-side Swift Version
Swift 4.1.3 is recommended and has been tested on Raspbian Stretch, Ubuntu Mate 16.04 and Ubuntu 16.04.  There are links at the top of [this page](https://www.uraimo.com/2018/06/13/A-big-update-on-Swift-4-1-2-for-raspberry-pi-zero-1-2-3/) to download different flavors of Linux and ARM hardware.
#### Use of a .local Host Domain
Note that your hostname on Linux must end with the local domain, for example:

```myhostname.local```
#### Avahi
You will need to install Avahi with the following Apt command to support publishing services under Linux:

```sudo apt install libavahi-compat-libdnssd-dev```
### Installation on iOS / tvOS and macOS
### CocoaPods
Coming soon.  For now use Carthage to intgrate the iOS/macOS/tvOS frameworks, or just clone the repo and add the files to your project directly.
### Carthage
Using a Cartfile, you get the ElementalController framework automatically compiled for iOS, tvOS, and macOS, without needing to worry about it's dependency on [BlueSocket](https://github.com/IBM-Swift/BlueSocket).  Here's what you need to add to your Cartfile, which must be located in your project directory:

`github "robreuss/ElementalController" ~> 0.0.4`

Then you run the command `carthage update` and you'll find the frameworks available in your project folder under "Carthage/Build".  You should only need to add ElementalController by dragging it from there to the Embedded Binaries section of your target, but not BlueSocket.

Learn more about [Carthage](https://github.com/Carthage/Carthage).
## Basic Use
### Sample Applications
The sample applications for [iOS](https://github.com/robreuss/ElementalController_iOS_Sample) and [Linux / macOS](https://github.com/robreuss/ElementalController_Linux_Sample) are the best way to get to know how to use ElementalController. 
### Client-Side 
Here's an example of setting up the framework with a few elements on the client side.  This is not a complete representation of available functionality.  

Counter-intuitively, elements and their handlers are defined first, and the command to connect follows that.

```swift
import ElementalController

// Elements are identified by an integer that
// gets transfered with it's value

enum ElementIdentifier: Int8 {
    
    case brightness = 1
    case backlight = 2

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
            brightness.value = Float(0.0)
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
import Foundation
import Dispatch
import Glibc

class MainProcess {

    // Hold a reference to our instance of EC so it doesn't deinitialize
    // You can have more than one of these to run multiple servers/clients
    var elementalController = ElementalController()
    
    // Element identifiers must be the same as the client side
    enum ElementIdentifier: Int8 {
        
        case brightness = 1
        case backlight = 2
        
    }
    
    func start() {

        elementalController.setupForService(serviceName: "screen_control", displayName: "My server")
        
        elementalController.service.events.deviceConnected.handler = { _, device in
                
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
                    logDebug("Server received a brightness element: \(element.value ?? "")")
                }
                
                backlight.handler = { element, _ in
                    logDebug("Server received a backlight element: \(element.value  ?? "")")
                }
                
        }
        
        // Setting this to port "0" will automatically select an available port
        elementalController.service.publish(onPort: 0)
    }
    
    
}

var process = MainProcess()
process.start()

// Prevent our instance of MainProcess from being destroyed
withExtendedLifetime((process)) {
    RunLoop.main.run()
}
```
## Thanks
ElementalController depends on the following projects:
#### NetService
Linux-side Zeroconf functionality (publishing and browsing of services) is thanks to [NetService](https://github.com/Bouke) by [Bouke Haarsma](https://github.com/Bouke).  
#### BlueSocket
TCP and UDP functionality is thanks to [BlueSocket](https://github.com/IBM-Swift/BlueSocket).
#### Swift on ARM Community
The Raspberry Pi capability in the framework depends upon the hard work of those who have brought Swift to ARM.





