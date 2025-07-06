import Testing
@testable import SwiftAgentKitMCP

@Suite("MCPModule Tests")
struct MCPModuleTests {
    @Test("Initialization")
    func testMCPModuleInitialization() throws {
        let module = MCPModule()
        #expect(module != nil)
    }
    
    @Test("Connect")
    func testMCPModuleConnect() throws {
        let module = MCPModule()
        // Just ensure connect doesn't crash
        module.connect()
    }
} 