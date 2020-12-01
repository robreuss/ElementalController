//
//  Logger
//
//
//  Created by Rob Reuss on 12/20/15.
//
//

import Foundation

public typealias RemoteLoggerHandler = ((LogLine) -> Void)?
public var remoteLoggerHandler: RemoteLoggerHandler?

var remoteLogging = RemoteLogging.shared

@objc public enum LogLevel: Int, CustomStringConvertible, Codable {
    case Error = 0
    case Debug = 1
    case Verbose = 2

    public var description: String {
        switch self {
            case .Error: return "Error"
            case .Debug: return "Debug"
            case .Verbose: return "Verbose"
        }
    }
}

func logAtLevel(_ priority: LogLevel, logLine: String) {
    if priority.rawValue <= ElementalController.loggerLogLevel.rawValue {
        if ElementalController.loggerUseNSLog {
            let nsLogLine = "[\(ElementalController.loggerPrefix)] \(logLine)" // Need to do this for Linux

            // There's an issue with printing to NSLog under Linux
            #if os(Linux)
            print("[\(ElementalController.loggerPrefix)] \(logLine)")
            #else
            NSLog("[\(ElementalController.loggerPrefix)] %@", nsLogLine)
            #endif

        } else {
            print("[\(ElementalController.loggerPrefix)] \(logLine)")
        }
        
        if let handler = remoteLoggerHandler {
            let logLineEnc = LogLine(text: logLine, logLevel: priority)
            handler!(logLineEnc)
        }
        
    }
}

func formatProtoForLogging(proto: Proto) -> String {
    return "[\(proto)]"
}

func formatServiceNameForLogging(serviceName: String) -> String {
    return "{\(serviceName)}"
}

func formatDeviceNameForLogging(deviceName: String) -> String {
    return "<\(deviceName)>"
}

func serviceNameForLogging(device: Device?) -> String {
    guard let d = device else { return "{No Service}" }
    return formatServiceNameForLogging(serviceName: d.serviceName)
}

func prefixForLogging(serviceName: String, proto: Proto) -> String {
    return "\(formatServiceNameForLogging(serviceName: serviceName)) \(formatProtoForLogging(proto: proto))"
}

func prefixForLogging(device: Device?, proto: Proto) -> String {
    return "\(serviceNameForLogging(device: device)) \(formatProtoForLogging(proto: proto))"
}

func prefixForLoggingServiceNameUsing(device: Device?) -> String {
    return "\(serviceNameForLogging(device: device))"
}

func prefixForLoggingDevice(device: Device?) -> String {
    return "\(serviceNameForLogging(device: device)) \(formatDeviceNameForLogging(deviceName: (device?.displayName)!))"
}

public func logVerbose(_ logLine: String) {
    logAtLevel(.Verbose, logLine: logLine)
}

public func logDebug(_ logLine: String) {
    logAtLevel(.Debug, logLine: logLine)
}

public func logError(_ logLine: String) {
    logAtLevel(.Error, logLine: "<<< ERROR >>> \(logLine)")
}
