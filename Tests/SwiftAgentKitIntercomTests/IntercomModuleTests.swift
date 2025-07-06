import Testing
@testable import SwiftAgentKitIntercom

@Suite("IntercomModule Tests")
struct IntercomModuleTests {
    @Test("Initialization")
    func testIntercomModuleInitialization() throws {
        let module = IntercomModule()
        #expect(module != nil)
    }
    
    @Test("Broadcast")
    func testIntercomModuleBroadcast() throws {
        let module = IntercomModule()
        // Just ensure broadcast doesn't crash
        module.broadcast("Test message")
    }
} 