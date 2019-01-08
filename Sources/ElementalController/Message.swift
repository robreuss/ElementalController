//
//  Message.swift
//  ElementalController
//
//  Created by Rob Reuss on 12/11/18.
//  Copyright © 2019 Rob Reuss. All rights reserved.
//

import Foundation

// Element envelope byte lengths
let HEADER_ID_LENGTH = 4
let ELEMENT_ID_LENGTH = 1
let ELEMENT_VALUE_LENGTH = 4
let UDP_ID_LENGTH = 1

// Calculate the beginning of the UDP ID, used in UDP Server
let UDP_ID_BEGINS = HEADER_ID_LENGTH + ELEMENT_ID_LENGTH + ELEMENT_VALUE_LENGTH

// This is returned as the identifier of the element if a number
// of different problematic conditions occur.
let MALFORMED_MESSAGE_IDENTIFIER: Int8 = -128

let MORE_COMING_IDENTIFIER: Int8 = -127

class Message {
    // Message header identifier is a random pre-generated 32-bit integer used
    // to indicate the start of a message.  It is not required but adds a layer
    // of confirmation of message flow.  An alternative would be to use a checksum
    // but that might have cpu time costs.
    static let headerIdentifierAsData = Data(bytes: &ElementalController.headerIdentifier, count: MemoryLayout<UInt32>.size)
    
    // The length of the header given circumstances and configuration options.
    func expectedHeaderLength(proto: Proto) -> Int {
        var requiredLength = ELEMENT_ID_LENGTH + ELEMENT_VALUE_LENGTH
        if ElementalController.requireHeaderIdentifier { requiredLength += HEADER_ID_LENGTH }
        if proto == .udp { requiredLength += UDP_ID_LENGTH }
        return requiredLength
    }
    
    // Use of this facility is controlled by ElementalController.enableTransferAnalysis
    // and ElementalController.transferAnalysisFrequency
    var performanceVars = PerformanceVars()
    struct PerformanceVars {
        var startTime: Date?
        var messagesReceived: Float = 0.0
        var bytesReceived: Int = 0
        var lastPublicationOfPerformance = Date()
        var invalidMessages: Float = 0.0
        var incompleteMessages: Float = 0.0
        var totalTransitTimeMeasurements: Double = 0.0
        var totalTransitTime: Double = 0.0
        var averageTransitTime: Double = 0.0
        var totalSessionMessages: Float = 0.0
        var bufferLoad: Int = 0
        var bufferCycles: Int = 0
        var bufferReads: Int = 0
        var maxLoad: Int = 0
        var lastTimeStamp: Double = 0.0
    }
    
    // If it seems the message is lacking integrity, return it with some indicator values and
    // clear the data buffer because it's pretty useless to try and intepret it.
    
    // TODO: Use a search for the header identifier, if available, to try to find the start
    // of a valid message.
    func malformedMessageResponse(details: String, proto: Proto, device: Device) -> (Int8, UInt8, Data, Data) {
        logError("\(prefixForLogging(device: device, proto: proto)) Malformed message: \(details)")
        if ElementalController.enableTransferAnalysis {
            self.self.performanceVars.invalidMessages += 1
        }
        return (MALFORMED_MESSAGE_IDENTIFIER, UInt8.max, Data(), Data())
    }
    
    // Main function, takes incoming message data that may contain more than one element message and
    // processes it, identifying the first element message in the stream and returining it's identifier,
    // value (in Data form still), and the remainder of the data sent in, which will be processed back
    // into this routine by the calling function.
    //
    // Prototype and a reference to the device are sent as parameters only for logging purposes.
    func process(data: Data, proto: Proto, device: Device) -> (elementIdentifier: Int8, udpIdentifier: UInt8, elementValue: Data, remainingData: Data) {
        var lengthOfValue: Int = 0
        var elementIdentifier: Int8
        var udpIdentifier: UInt8 = UInt8.max
        
        // Data pointer is a cursor that moves forward as we extract the components of the header,
        // plus the value (which has an aribtrary length indicated by ELEMENT_VALUE_LENGTH factor.
        var dataPointer = 0
        
        // Test the header ID against an aribitrary header ID pre-set on all instances of the app (both
        // client and server).  This can be disabled to save bandwidth.
        if ElementalController.requireHeaderIdentifier {
            if data.count >= HEADER_ID_LENGTH {
                let headerID = data.subdata(in: dataPointer..<HEADER_ID_LENGTH)
                dataPointer += HEADER_ID_LENGTH
                if headerID != Message.headerIdentifierAsData {

                    return malformedMessageResponse(details: "Non-matching header ID", proto: proto, device: device)
                }
            } else {
                
                logDebug("\(formatProtoForLogging(proto: proto)) Data too short to have header ID (\(data.count)), fetching more data")
                
                // In this case, we don't reset the data stream in the hopes that we'll
                // get more data that restores the integrity of the current message.
                return (MORE_COMING_IDENTIFIER, udpIdentifier, Data(), data)
                
                //return malformedMessageResponse(details: "Message processor found no header identifier. ", proto: proto, device: device)
            }
        }
        
        // Test for a enough data for a header (plus one byte for at least a byte of data)
        if data.count < expectedHeaderLength(proto: proto)  {
           performanceVars.incompleteMessages += 1
            return (MORE_COMING_IDENTIFIER, udpIdentifier, Data(), data)
            //return malformedMessageResponse(details: "Message processor found too little data for a header. ", proto: proto, device: device)
        }
        
        // The element identifier tells us which amoung the set of user-defined elements the message represents.
        let elementIdentifierAsData = data.subdata(in: dataPointer..<(dataPointer + ELEMENT_ID_LENGTH))
        elementIdentifier = Element.int8Value(data: elementIdentifierAsData)
        dataPointer += ELEMENT_ID_LENGTH
        
        let lengthOfValueAsData = data.subdata(in: dataPointer..<dataPointer + ELEMENT_VALUE_LENGTH)
        lengthOfValue = Int(Element.int32Value(data: lengthOfValueAsData))
        if lengthOfValue < 1 {
            return malformedMessageResponse(details: "Element (\(elementIdentifier)) length of value is less than 1.", proto: proto, device: device)
        }
        dataPointer += ELEMENT_VALUE_LENGTH
        
        if proto == .udp {
            let udpIdentifierAsData = data.subdata(in: dataPointer..<dataPointer + UDP_ID_LENGTH)
            udpIdentifier = UInt8(Element.uint8Value(data: udpIdentifierAsData))
            dataPointer += UDP_ID_LENGTH
        }
        
        if data.count < (dataPointer + lengthOfValue) {
            logVerbose("\(formatProtoForLogging(proto: proto)) Streamer fetching additional data: current bytes = \(data.count)")
            
            performanceVars.incompleteMessages += 1
            // In this case, we don't reset the data stream in the hopes that we'll
            // get more data that restores the integrity of the current message.
            return (MORE_COMING_IDENTIFIER, udpIdentifier, Data(), data)
        }
        
        if data.count < dataPointer + lengthOfValue  {
            return malformedMessageResponse(details: "Length of data is inadequate to the header indication of length.", proto: proto, device: device)
        }
        
        var elementValueData: Data = data.subdata(in: dataPointer..<dataPointer + lengthOfValue)
        let dataRemainingAfterCurrentElement = data.subdata(in: dataPointer + lengthOfValue..<data.count)

        // TODO: Re-enable performance testing
        if elementValueData.count == lengthOfValue {
            if ElementalController.enableTransferAnalysis {
                self.performanceVars.bytesReceived += dataPointer + lengthOfValue
                let currentBuffer = data.count - (dataPointer + lengthOfValue) // Consider the buffer to be the total data being processed minus the current message data
                if currentBuffer > self.performanceVars.maxLoad { self.performanceVars.maxLoad = currentBuffer }
                self.performanceVars.bufferLoad += currentBuffer
                self.performanceVars.bufferCycles += 1
                self.doPerformanceTesting(device: device, proto: proto)
                logVerbose("\(formatProtoForLogging(proto: proto)) Message Processor: \(data.count) bytes in, header length: \(dataPointer), expected value length: \(lengthOfValue), total expected bytes: \(dataPointer + lengthOfValue), remainder: \(dataRemainingAfterCurrentElement.count), udpIdentifier: \(udpIdentifier)")
            }
            return (elementIdentifier, udpIdentifier, elementValueData, dataRemainingAfterCurrentElement)
            
        } else {
            // We found no element, so return the whole set of data as a remainder
            logDebug("Returning all data as a remainder \(dataRemainingAfterCurrentElement.count)")
            return (MALFORMED_MESSAGE_IDENTIFIER, udpIdentifier, Data(), data as Data)
        }
    }
    
    func doPerformanceTesting(device: Device, proto: Proto) {
        // Performance testing is about calculating elements received per second
        // By sending motion data, it can be  compared to expected rates.
        
        if self.performanceVars.startTime == nil { self.performanceVars.startTime = Date() }
        
        self.performanceVars.messagesReceived += 1
        if Float(self.performanceVars.lastPublicationOfPerformance.timeIntervalSinceNow) < -(ElementalController.transferAnalysisFrequency) {
            let messagesPerSecond: Float = self.performanceVars.messagesReceived / ElementalController.transferAnalysisFrequency
            var kbPerSecond: Float = (Float(self.performanceVars.bytesReceived) / ElementalController.transferAnalysisFrequency) / 1000
            kbPerSecond.round()
            var averageBufferLoad: Float = Float(self.performanceVars.bufferLoad) / Float(self.performanceVars.bufferCycles)
            averageBufferLoad.round()
            var kilobytesReceived: Float = Float(self.performanceVars.bytesReceived) / 1000.0
            kilobytesReceived.round()
            self.performanceVars.totalSessionMessages += self.performanceVars.messagesReceived
            var elapsedTimeMinutes = ((self.performanceVars.startTime?.timeIntervalSinceNow)! / 60) * 10
            elapsedTimeMinutes.round()
            elapsedTimeMinutes = abs(elapsedTimeMinutes / 10)
            logDebug("\(proto.description.uppercased()): \(device.serviceName): [\(device.displayName)]: \(self.performanceVars.messagesReceived) msgs (\(self.performanceVars.totalSessionMessages) total), \(messagesPerSecond) msgs/sec, \(self.performanceVars.incompleteMessages) required more, \(self.performanceVars.invalidMessages) malformed, \(kbPerSecond) KB/sec rcvd, \(kilobytesReceived) KB rcvd , Max buffer \(self.performanceVars.maxLoad) bytes, avg buffer \(averageBufferLoad) bytes")
            self.performanceVars.messagesReceived = 0
            self.performanceVars.invalidMessages = 0
            self.performanceVars.incompleteMessages = 0
            self.performanceVars.lastPublicationOfPerformance = Date()
            self.performanceVars.bytesReceived = 0
            self.performanceVars.bufferLoad = 0
            self.performanceVars.bufferCycles = 0
            self.performanceVars.bufferReads = 0
            self.performanceVars.maxLoad = 0
        }
    }
}
