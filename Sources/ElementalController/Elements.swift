//
//  Elements.swift
//  ElementalController
//
//  Created by Rob Reuss on 12/6/18.
//  Copyright © 2019 Rob Reuss. All rights reserved.
//

// TODO: Be sure to add to documentation that negative numbers cannot be used
// as element identifiers

import Foundation
import Dispatch

var udpIdentifier: Int32 = 0

enum SystemElements: Int8 {
    case udpIdentifier = -1 // UDP is connectionless so each element message needs to identify the device
    case deviceName = -2 // Client to server because server name is known via zeroconf
    case shutdownMessage = -3 // Client to server because server name is known via zeroconf
}

public enum ElementDataType: Int {
    case Int8 = 0
    case UInt8 = 1
    case Int16 = 2
    case UInt16 = 3
    case Int32 = 4
    case UInt32 = 5
    case Int64 = 6
    case UInt64 = 7
    case Float = 8
    case Double = 9
    case String = 10
    case Data = 11
}

// Core data structure class representing a real-world control or sensor, that
// is transmitted as a message by the framework.
public class Element {
    
    let elementReadWriteLock = DispatchQueue(label: "net.simplyformed.elementReadWriteLock")
    
    public typealias ElementHandler = ((Element, Device) -> Void)?
    public var handler: ElementHandler

    public var identifier: Int8 = 0
    public var displayName: String
    var readValue = "" as Any
    var writeValue = "" as Any
    public var proto: Proto = .tcp
    public var useFilter: Bool = false
    public var dataType: ElementDataType = .String

    // TODO: Reconsider the need for two initializers here
    // Need this initializing udpIdentifierElement in Device
    init() {
        self.identifier = 0
        self.displayName = "None"
        self.proto = .tcp
        self.dataType = .Int16
    }
    
    public init(identifier: Int8, displayName: String, proto: Proto, dataType: ElementDataType) {
        self.identifier = identifier
        self.displayName = displayName
        self.proto = proto
        self.dataType = dataType
    }
    
    // Should almost always execute throwing back onto the main thread,
    // but just in case, we test for current execution context.
    func executeHandlers(element: Element, device: Device) {
        guard let h = handler else { return }
            if Thread.isMainThread {
                h(self, device)
            } else {
                (DispatchQueue.main).sync {
                    h(self, device)
                }
            }
    }
    
    //public func handler(_ : ElementHandler) {
     //   privateHandler = handler
    //}

    
    // MARK: -
    
    func encodeAsMessage(udpIdentifier: UInt8) -> Data {
        
        var identifierAsUInt8: Int8 = Int8(identifier)
        let identifierAsData = Data(bytes: &identifierAsUInt8, count: MemoryLayout<Int8>.size)
        
        var lengthAsUInt32: UInt32 = UInt32(valueAsData.count)
        let lengthAsData = Data(bytes: &lengthAsUInt32, count: MemoryLayout<UInt32>.size)
        
        var messageData = Data()
        
        if ElementalController.requireHeaderIdentifier {
            messageData.append(Message.headerIdentifierAsData) // 4 bytes:   indicates the start of an individual message, random 32-bit int
        }
        messageData.append(identifierAsData) // 1 byte:    identifies the type of the element
        
        messageData.append(lengthAsData) // 4 bytes:   length of the message
        
        if proto == .udp {
            var udpIdentifierInt8: UInt8 = UInt8(udpIdentifier)
            let udpIdentifierData = Data(bytes: &udpIdentifierInt8, count: MemoryLayout<UInt8>.size)
            messageData.append(udpIdentifierData) // 2 bytes:  Central this element is destined for
        }
        
        messageData.append(valueAsData)

        return messageData
    }
    
    
    // MARK: -

    // We keep a private version to test for type before returning
    public var value: Any? {
        get {

            switch dataType {
            case .Int8:
                return readValue is Int8 ? readValue : nil
            case .UInt8:
                return readValue is UInt8 ? readValue : nil
            case .Int16:
                return readValue is Int16 ? readValue : nil
            case .UInt16:
                return readValue is UInt16 ? readValue : nil
            case .Int32:
                return readValue is Int32 ? readValue : nil
            case .UInt32:
                return readValue is UInt32 ? readValue : nil
            case .Int64:
                return readValue is Int64 ? readValue : nil
            case .UInt64:
                return readValue is UInt64 ? readValue : nil
            case .Float:
                return readValue is Float ? readValue : nil
            case .Double:
                return readValue is Double ? readValue : nil
            case .String:
                return readValue is String ? readValue : nil
            case .Data:
                return readValue is Data ? readValue : nil
            }

        }
        set {
            elementReadWriteLock.sync {
                writeValue = newValue as Any
            }

        }
    }


    // MARK: -
    
    var valueAsData: Data {
        
        get {
            let error = "\(displayName) (\(identifier)) nil encountered when encoding value as data (possible type error)."

            switch dataType {
            case .Int8:
                if var value = writeValue as? Int8 {
                    return Data(bytes: &value, count: MemoryLayout.size(ofValue: value))
                } else {
                    logError("Attempted to encode Int8 element \"\(displayName)\" failed - wrong type")
                    fatalError()
                }
                
            case .UInt8:
                if var value = writeValue as? UInt8 {
                    return Data(bytes: &value, count: MemoryLayout.size(ofValue: value))
                } else {
                    logError("Attempted to encode UInt8 element \"\(displayName)\" failed - wrong type")
                    fatalError()
                }
                
            case .Int16:
                
                if var value = writeValue as? Int16 {
                    return Data(bytes: &value, count: MemoryLayout.size(ofValue: value))
                } else {
                    logError("Attempted to encode Int16 element \"\(displayName)\" failed - wrong type")
                    fatalError()
                }
                
            case .UInt16:
                
                if var value = writeValue as? UInt16 {
                    return Data(bytes: &value, count: MemoryLayout.size(ofValue: value))
                } else {
                    logError("Attempted to encode UInt16 element \"\(displayName)\" failed - wrong type")
                    fatalError()
                }
                
            case .Int32:
                
                if var value = writeValue as? Int32 {
                    return Data(bytes: &value, count: MemoryLayout.size(ofValue: value))
                } else {
                    logError("Attempted to encode Int32 element \"\(displayName)\" failed - wrong type")
                    fatalError()
                }
                
            case .UInt32:
                
                if var value = writeValue as? UInt32 {
                    return Data(bytes: &value, count: MemoryLayout.size(ofValue: value))
                } else {
                    logError("Attempted to encode UInt32 element \"\(displayName)\" failed - wrong type")
                    fatalError()
                }
                
            case .Int64:
                
                if var value = writeValue as? Int64 {
                    return Data(bytes: &value, count: MemoryLayout.size(ofValue: value))
                } else {
                    logError("Attempted to encode Int64 element \"\(displayName)\" failed - wrong type")
                    fatalError()
                }
                
            case .UInt64:
                
                if var value = writeValue as? UInt64 {
                    return Data(bytes: &value, count: MemoryLayout.size(ofValue: value))
                } else {
                    logError("Attempted to encode UInt64 element \"\(displayName)\" failed - wrong type")
                    fatalError()
                }
                
            case .Float:
                
                if var value = writeValue as? Float {
                    return Data(bytes: &value, count: MemoryLayout.size(ofValue: value))
                } else {
                    logError("Attempted to encode Float element \"\(displayName)\" failed - wrong type")
                    fatalError()
                }
                
            case .Double:
                
                if var value = writeValue as? Double {
                    return Data(bytes: &value, count: MemoryLayout.size(ofValue: value))
                } else {
                    logError("Attempted to encode Double element \"\(displayName)\" failed - wrong type")
                    fatalError()
                }
                
            case .Data:
                
                if var value = writeValue as? Data {
                    return writeValue as! Data
                } else {
                    logError("Attempted to encode Double element \"\(displayName)\" failed - wrong type")
                    fatalError()
                }
                
            case .String:
                
                var returnData = Data()
                elementReadWriteLock.sync {
                    if let myData = (writeValue as! String).data(using: String.Encoding.utf8) {
                        returnData = myData
                    } else {
                        logError("Element got nil when expecting string data")
                        returnData = Data()
                    }
                }
                return returnData
            }
        }
        
        set {
            elementReadWriteLock.sync {
                
                switch dataType {
                case .Int8:
                    let int = Element.int8Value(data: newValue)
                    readValue = int as Any
                    
                case .UInt8:
                    let int = Element.uint8Value(data: newValue)
                    readValue = int as Any
                    
                case .Int16:
                    
                    let int = Element.int16Value(data: newValue)
                    readValue = int as Any
                    
                case .UInt16:
                    
                    let int = Element.uint16Value(data: newValue)
                    readValue = int as Any
                    
                case .Int32:
                    
                    let int = Element.int32Value(data: newValue)
                    readValue = int as Any
                    
                case .UInt32:
                    
                    let int = Element.uint32Value(data: newValue)
                    readValue = int as Any
                    
                case .Int64:
                    
                    let int = Element.int64Value(data: newValue)
                    readValue = int as Any
                    
                case .UInt64:
                    
                    let int = Element.uint64Value(data: newValue)
                    readValue = int as Any
                    
                case .Float:
                    
                    let float = Element.floatValue(data: newValue)
                    readValue = float as Any
                    
                case .Double:

                    let double = Element.doubleValue(data: newValue)
                    readValue = double as Any
                    
                case .Data:
                    readValue = newValue as Any
                    
                case .String:
                    if let s = String(data: newValue, encoding: String.Encoding.utf8) {
                        readValue = s
                    } else {
                        logError("\(displayName) (\(identifier)) Element of type \(dataType) got nil while encoding to bytes")
                        
                    }
                }
            }
        }
    }
    
    
    // MARK: -
    // MARK: Convert Data to typed values

    static func int8Value(data: Data) -> Int8 {
        return Int8(bitPattern: UInt8(littleEndian: data.withUnsafeBytes { $0.pointee }))
    }
    
    static func uint8Value(data: Data) -> UInt8 {
        return data.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> UInt8 in
            ptr.pointee
        }
    }
    
    static func int16Value(data: Data) -> Int16 {
        return Int16(bitPattern: UInt16(littleEndian: data.withUnsafeBytes { $0.pointee }))
    }
    
    // TODO: Update other functions to use this pattern
    static func uint16Value(data: Data) -> UInt16 {
        return data.withUnsafeBytes { (ptr: UnsafePointer<UInt16>) -> UInt16 in
            ptr.pointee
        }
    }
    
    static func int32Value(data: Data) -> Int32 {
        return Int32(bitPattern: UInt32(littleEndian: data.withUnsafeBytes { $0.pointee }))
    }
    
    static func uint32Value(data: Data) -> UInt32 {
        return data.withUnsafeBytes { (ptr: UnsafePointer<UInt32>) -> UInt32 in
            ptr.pointee
        }
    }
    
    static func int64Value(data: Data) -> Int64 {
        return Int64(bitPattern: UInt64(littleEndian: data.withUnsafeBytes { $0.pointee }))
    }
    
    static func uint64Value(data: Data) -> UInt64 {
        return data.withUnsafeBytes { (ptr: UnsafePointer<UInt64>) -> UInt64 in
            ptr.pointee
        }
    }
    
    static func floatValue(data: Data) -> Float {
        return Float(bitPattern: UInt32(littleEndian: data.withUnsafeBytes { $0.pointee }))
    }
    
    static func doubleValue(data: Data) -> Double {
        return Double(bitPattern: UInt64(littleEndian: data.withUnsafeBytes { $0.pointee }))
    }
}
