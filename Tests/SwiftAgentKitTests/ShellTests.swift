//
//  ShellTests.swift
//  SwiftAgentKitTests
//

import Foundation
import Testing
@testable import SwiftAgentKit

#if os(macOS) || os(Linux)

@Suite("Shell cwd resolution")
struct ShellTests {

    @Test("resolveExistingDirectory prefers an existing preferred path")
    func testResolvePreferred() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let resolved = Shell.resolveExistingDirectory(
            preferred: dir,
            environment: ["PWD": "/tmp", "HOME": NSHomeDirectory()]
        )
        #expect(resolved.standardizedFileURL.path == dir.standardizedFileURL.path)
    }

    @Test("resolveExistingDirectory falls back to PWD when preferred is missing")
    func testResolveFallsBackToPWD() throws {
        let pwd = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: pwd) }
        let missing = URL(fileURLWithPath: "/definitely/does/not/exist-\(UUID().uuidString)", isDirectory: true)

        let resolved = Shell.resolveExistingDirectory(
            preferred: missing,
            environment: ["PWD": pwd.path, "HOME": NSHomeDirectory()]
        )
        #expect(resolved.standardizedFileURL.path == pwd.standardizedFileURL.path)
    }

    @Test("resolveExistingDirectory falls back to HOME when PWD is missing")
    func testResolveFallsBackToHOME() {
        let home = NSHomeDirectory()
        let resolved = Shell.resolveExistingDirectory(
            preferred: URL(fileURLWithPath: "/definitely/does/not/exist-\(UUID().uuidString)", isDirectory: true),
            environment: [
                "PWD": "/definitely/also/missing-\(UUID().uuidString)",
                "HOME": home
            ]
        )
        #expect(resolved.standardizedFileURL.path == URL(fileURLWithPath: home, isDirectory: true).standardizedFileURL.path)
    }

    @Test("explicit currentDirectory is used by child getcwd")
    func testExplicitCurrentDirectory() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let output = try runPwd(
            environment: minimalEnv(home: NSHomeDirectory()),
            currentDirectory: dir
        )
        #expect(output == dir.standardizedFileURL.path)
    }

    @Test("existing PWD in environment is used when currentDirectory is nil")
    func testExistingPWD() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        var env = minimalEnv(home: NSHomeDirectory())
        env["PWD"] = dir.path

        let output = try runPwd(environment: env, currentDirectory: nil)
        #expect(output == dir.standardizedFileURL.path)
    }

    @Test("missing preferred currentDirectory falls back to existing PWD")
    func testMissingPreferredFallsBackToPWD() throws {
        let pwd = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: pwd) }
        let missing = URL(fileURLWithPath: "/definitely/does/not/exist-\(UUID().uuidString)", isDirectory: true)

        var env = minimalEnv(home: NSHomeDirectory())
        env["PWD"] = pwd.path

        let output = try runPwd(environment: env, currentDirectory: missing)
        #expect(output == pwd.standardizedFileURL.path)
    }

    @Test("when parent cwd is deleted, child getcwd uses HOME not the deleted path")
    func testDeletedParentCwdFallsBackToHOME() throws {
        let fm = FileManager.default
        let originalCwd = fm.currentDirectoryPath
        let ephemeral = try makeTempDirectory()
        let home = NSHomeDirectory()

        #expect(fm.changeCurrentDirectoryPath(ephemeral.path))
        defer {
            _ = fm.changeCurrentDirectoryPath(originalCwd)
        }

        try fm.removeItem(at: ephemeral)

        let output = try runPwd(
            environment: minimalEnv(home: home),
            currentDirectory: nil
        )
        #expect(output == URL(fileURLWithPath: home, isDirectory: true).standardizedFileURL.path)
        #expect(output != ephemeral.path)
    }

    // MARK: - Helpers

    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShellTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.standardizedFileURL
    }

    private func minimalEnv(home: String) -> [String: String] {
        [
            "HOME": home,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
        ]
    }

    private func runPwd(environment: [String: String], currentDirectory: URL?) throws -> String {
        let launched = Shell.launchSubprocess(
            command: "/bin/pwd",
            arguments: [],
            environment: environment,
            currentDirectory: currentDirectory,
            useShell: false
        )
        try launched.inPipe.fileHandleForWriting.close()
        launched.process.waitUntilExit()
        let data = launched.outPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        #expect(launched.process.terminationStatus == 0)
        return URL(fileURLWithPath: output, isDirectory: true).standardizedFileURL.path
    }
}

#endif
