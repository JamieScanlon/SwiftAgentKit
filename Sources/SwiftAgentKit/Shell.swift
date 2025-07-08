//
//  Shell.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 4/12/25.
//

import Foundation

public struct Shell {
    
    public static func shell(_ command: String, environment: [String: String] = [:]) -> (inPipe: Pipe, outPipe: Pipe) {
        let task = Process()
        let inPipe = Pipe()
        let outPipe = Pipe()
        
        task.standardOutput = outPipe
        task.standardError = outPipe
        task.environment = environment
        task.arguments = ["-c", command]
        task.launchPath = "/bin/zsh"
        task.standardInput = inPipe
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
        task.standardOutput = outPipe
        task.standardError = outPipe
        task.environment = environment
        task.arguments = ["-c", fullCommandString]
        task.launchPath = "/bin/zsh"
        task.standardInput = inPipe
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
