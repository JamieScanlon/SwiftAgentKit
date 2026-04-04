//
//  Shell.swift
//  SwiftAgentKit
//
//  Created by Marvin Scanlon on 4/12/25.
//

#if os(macOS) || os(Linux) || os(Windows)
import Foundation
import Logging

#if canImport(Darwin)
import Darwin
#elseif os(Linux)
import Glibc
#endif

public struct Shell {
    private static let logger = SwiftAgentKitLogging.logger(
        for: .core("Shell")
    )

    /// Launches a subprocess with stdio wired to pipes, retaining the ``Process`` handle for lifecycle control.
    /// - Parameters:
    ///   - command: Executable name (resolved via `PATH`) or path when `useShell` is false on Unix (via `/usr/bin/env`).
    ///   - arguments: Arguments passed to the command (not used as shell syntax unless `useShell` is true).
    ///   - environment: Environment for the child process.
    ///   - useShell: When true, runs the command through a shell (`zsh -c` on Unix, `cmd /c` on Windows) so shell features work.
    ///     When false (default), uses `/usr/bin env command arg1 arg2 …` on Unix for a direct, terminable process tree.
    /// - Returns: The launched ``Process`` and pipes where the parent writes to the child’s stdin (`inPipe`) and reads merged stdout/stderr (`outPipe`).
    public static func launchSubprocess(
        command: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        useShell: Bool = false
    ) -> (process: Process, inPipe: Pipe, outPipe: Pipe) {
        let task = Process()
        let inPipe = Pipe()
        let outPipe = Pipe()

        let metadata: Logger.Metadata = [
            "command": .string(command),
            "argumentCount": .stringConvertible(arguments.count),
            "useShell": .string(useShell ? "true" : "false"),
            "environmentKeys": .string(environment.keys.sorted().joined(separator: ",")),
            "environmentCount": .stringConvertible(environment.count)
        ]
        logger.info("Launching subprocess", metadata: metadata)

        task.standardOutput = outPipe
        task.standardError = outPipe
        task.environment = environment
        task.standardInput = inPipe

        if useShell {
            configureShellInvocation(task: task, command: command, arguments: arguments)
        } else {
            configureDirectInvocation(task: task, command: command, arguments: arguments)
        }

        task.terminationHandler = { process in
            Self.logger.info(
                "Subprocess finished",
                metadata: [
                    "command": .string(command),
                    "argumentCount": .stringConvertible(arguments.count),
                    "terminationReason": .string(process.terminationReason == .exit ? "exit" : "uncaughtSignal"),
                    "status": .stringConvertible(process.terminationStatus)
                ]
            )
        }

        task.launch()
        return (process: task, inPipe: inPipe, outPipe: outPipe)
    }

    private static func configureShellInvocation(task: Process, command: String, arguments: [String]) {
        #if os(Windows)
        let comSpec = ProcessInfo.processInfo.environment["ComSpec"] ?? #"C:\Windows\System32\cmd.exe"#
        task.executableURL = URL(fileURLWithPath: comSpec)
        let fullCommandString = "\(command) \(arguments.joined(separator: " "))"
        task.arguments = ["/c", fullCommandString]
        #else
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        let fullCommandString = "\(command) \(arguments.joined(separator: " "))"
        task.arguments = ["-c", fullCommandString]
        #endif
    }

    private static func configureDirectInvocation(task: Process, command: String, arguments: [String]) {
        #if os(Windows)
        let comSpec = ProcessInfo.processInfo.environment["ComSpec"] ?? #"C:\Windows\System32\cmd.exe"#
        task.executableURL = URL(fileURLWithPath: comSpec)
        let fullCommandString = "\(command) \(arguments.joined(separator: " "))"
        task.arguments = ["/c", fullCommandString]
        #else
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = [command] + arguments
        #endif
    }

    /// Sends SIGTERM, waits up to `gracePeriod`, then sends SIGKILL if still running (Unix). On Windows, only SIGTERM via ``Process/terminate()`` is guaranteed.
    public static func terminateProcess(_ process: Process, gracePeriod: TimeInterval = 2.0) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(gracePeriod)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard process.isRunning else { return }
        #if !os(Windows)
        let pid = pid_t(process.processIdentifier)
        kill(pid, SIGKILL)
        #endif
        while process.isRunning {
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    public static func shell(_ command: String, environment: [String: String] = [:]) -> (process: Process, inPipe: Pipe, outPipe: Pipe) {
        launchSubprocess(command: command, arguments: [], environment: environment, useShell: true)
    }

    public static func shell(_ command: String, arguments: [String] = [], environment: [String: String] = [:]) -> (process: Process, inPipe: Pipe, outPipe: Pipe) {
        launchSubprocess(command: command, arguments: arguments, environment: environment, useShell: true)
    }
}
#endif
