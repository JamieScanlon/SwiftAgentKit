//
//  Shell.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 4/12/25.
//

#if os(macOS) || os(Linux) || os(Windows)
import Foundation
import Logging

public struct Shell {
    private static let logger = SwiftAgentKitLogging.logger(
        for: .core("Shell")
    )
    
    public static func shell(_ command: String, environment: [String: String] = [:]) -> (inPipe: Pipe, outPipe: Pipe) {
        let task = Process()
        let inPipe = Pipe()
        let outPipe = Pipe()
        let metadata: Logger.Metadata = [
            "command": .string(command),
            "environmentKeys": .string(environment.keys.sorted().joined(separator: ",")),
            "environmentCount": .stringConvertible(environment.count)
        ]
        logger.info("Launching shell command", metadata: metadata)
        
        task.standardOutput = outPipe
        task.standardError = outPipe
        task.environment = environment
        task.arguments = ["-c", command]
        task.launchPath = "/bin/zsh"
        task.standardInput = inPipe
        task.terminationHandler = { process in
            Self.logger.info(
                "Shell command finished",
                metadata: [
                    "command": .string(command),
                    "terminationReason": .string(process.terminationReason == .exit ? "exit" : "uncaughtSignal"),
                    "status": .stringConvertible(process.terminationStatus)
                ]
            )
        }

//        task.standardInput = nil
        task.launch()
        
//        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
//        let output = String(data: data, encoding: .utf8)!
//        print(output)
//        
        return (inPipe: inPipe, outPipe: outPipe)
    }
    
    public static func shell(_ command: String, arguments: [String] = [], environment: [String: String] = [:]) -> (inPipe: Pipe, outPipe: Pipe) {
        let task = Process()
        let inPipe = Pipe()
        let outPipe = Pipe()
        
        let fullCommandString = "\(command) \(arguments.joined(separator: " "))"
        let metadata: Logger.Metadata = [
            "command": .string(command),
            "argumentCount": .stringConvertible(arguments.count),
            "environmentKeys": .string(environment.keys.sorted().joined(separator: ",")),
            "environmentCount": .stringConvertible(environment.count)
        ]
        logger.info("Launching shell command with arguments", metadata: metadata)

        task.standardOutput = outPipe
        task.standardError = outPipe
        task.environment = environment
        task.arguments = ["-c", fullCommandString]
        task.launchPath = "/bin/zsh"
        task.standardInput = inPipe
        task.terminationHandler = { process in
            Self.logger.info(
                "Shell command finished",
                metadata: [
                    "command": .string(command),
                    "argumentCount": .stringConvertible(arguments.count),
                    "terminationReason": .string(process.terminationReason == .exit ? "exit" : "uncaughtSignal"),
                    "status": .stringConvertible(process.terminationStatus)
                ]
            )
        }

//        task.standardInput = nil
        task.launch()
        
//        if let data = try! FileHandle.standardOutput.readToEnd() {
//            let output = String(data: data, encoding: .utf8)!
//            print(output)
//        }
//        outPipe.fileHandleForReading.readabilityHandler = { fileHandle in
//            let data = fileHandle.availableData
//            let output = String(data: data, encoding: .utf8)!
//            print(output)
//        }
        
        
        return (inPipe: inPipe, outPipe: outPipe)
    }
}
#endif
