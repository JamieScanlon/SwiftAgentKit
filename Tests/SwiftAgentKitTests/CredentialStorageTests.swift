import Testing
import Foundation
@testable import SwiftAgentKit

struct CredentialStorageTests {
    
    @Test("Store and Load Credentials")
    func testStoreAndLoadCredentials() async {
        let userDefaults = UserDefaults(suiteName: "test-store-load-\(UUID().uuidString)")!
        let storage = DefaultDynamicClientCredentialStorage(userDefaults: userDefaults)
        
        let credentials = DynamicClientRegistration.ClientRegistrationResponse(
            clientId: "test-client-123",
            clientSecret: "test-secret-456",
            clientIdIssuedAt: 1234567890,
            clientSecretExpiresAt: nil,
            redirectUris: ["https://example.com/callback"],
            applicationType: "native",
            clientName: "Test Client",
            scope: "mcp"
        )
        
        // Store credentials
        await storage.storeCredentials(credentials)
        
        // Load credentials for the specific client
        let loadedCredentials = await storage.loadCredentials(for: "test-client-123")
        
        #expect(loadedCredentials != nil)
        #expect(loadedCredentials?.clientId == "test-client-123")
        #expect(loadedCredentials?.clientSecret == "test-secret-456")
        #expect(loadedCredentials?.clientName == "Test Client")
        #expect(loadedCredentials?.scope == "mcp")
    }
    
    @Test("Clear Credentials")
    func testClearCredentials() async {
        let userDefaults = UserDefaults(suiteName: "test-clear-\(UUID().uuidString)")!
        let storage = DefaultDynamicClientCredentialStorage(userDefaults: userDefaults)
        
        let credentials = DynamicClientRegistration.ClientRegistrationResponse(
            clientId: "test-client-789",
            clientSecret: "test-secret-101112",
            clientIdIssuedAt: 1234567890,
            clientSecretExpiresAt: nil,
            redirectUris: ["https://example.com/callback"],
            applicationType: "native",
            clientName: "Test Client",
            scope: "mcp"
        )
        
        // Store credentials
        await storage.storeCredentials(credentials)
        
        // Verify they're stored
        let loadedCredentials = await storage.loadCredentials(for: "test-client-789")
        #expect(loadedCredentials?.clientId == "test-client-789")
        
        // Clear credentials
        await storage.clearCredentials(clientId: "test-client-789")
        
        // Verify they're cleared
        let clearedCredentials = await storage.loadCredentials(for: "test-client-789")
        #expect(clearedCredentials == nil)
    }
    
    @Test("Clear All Credentials")
    func testClearAllCredentials() async {
        let userDefaults = UserDefaults(suiteName: "test-clear-all-\(UUID().uuidString)")!
        let storage = DefaultDynamicClientCredentialStorage(userDefaults: userDefaults)
        
        let credentials1 = DynamicClientRegistration.ClientRegistrationResponse(
            clientId: "test-client-1",
            clientSecret: "test-secret-1",
            clientIdIssuedAt: 1234567890,
            clientSecretExpiresAt: nil,
            redirectUris: ["https://example.com/callback"],
            applicationType: "native",
            clientName: "Test Client 1",
            scope: "mcp"
        )
        
        let credentials2 = DynamicClientRegistration.ClientRegistrationResponse(
            clientId: "test-client-2",
            clientSecret: "test-secret-2",
            clientIdIssuedAt: 1234567890,
            clientSecretExpiresAt: nil,
            redirectUris: ["https://example.com/callback2"],
            applicationType: "native",
            clientName: "Test Client 2",
            scope: "mcp"
        )
        
        // Store multiple credentials
        await storage.storeCredentials(credentials1)
        await storage.storeCredentials(credentials2)
        
        // Verify they're stored
        let loadedCredentials1 = await storage.loadCredentials(for: "test-client-1")
        let loadedCredentials2 = await storage.loadCredentials(for: "test-client-2")
        #expect(loadedCredentials1 != nil)
        #expect(loadedCredentials2 != nil)
        
        // Clear all credentials
        await storage.clearAllCredentials()
        
        // Verify they're all cleared
        let clearedCredentials1 = await storage.loadCredentials(for: "test-client-1")
        let clearedCredentials2 = await storage.loadCredentials(for: "test-client-2")
        #expect(clearedCredentials1 == nil)
        #expect(clearedCredentials2 == nil)
    }
    
    @Test("Credential Storage Protocol Conformance")
    func testCredentialStorageProtocolConformance() async {
        // Test that DefaultDynamicClientCredentialStorage conforms to the protocol
        let userDefaults = UserDefaults(suiteName: "test-protocol-\(UUID().uuidString)")!
        let storage: DynamicClientCredentialStorage = DefaultDynamicClientCredentialStorage(userDefaults: userDefaults)
        
        let credentials = DynamicClientRegistration.ClientRegistrationResponse(
            clientId: "test-client-protocol",
            clientSecret: "test-secret-protocol",
            clientIdIssuedAt: 1234567890,
            clientSecretExpiresAt: nil,
            redirectUris: ["https://example.com/callback"],
            applicationType: "native",
            clientName: "Test Client Protocol",
            scope: "mcp"
        )
        
        // Test basic protocol operations
        await storage.storeCredentials(credentials)
        let loadedCredentials = await storage.loadCredentials(for: "test-client-protocol")
        
        #expect(loadedCredentials != nil)
        #expect(loadedCredentials?.clientId == "test-client-protocol")
        
        await storage.clearCredentials(clientId: "test-client-protocol")
        let clearedCredentials = await storage.loadCredentials(for: "test-client-protocol")
        
        // After clearing, we should get nil
        #expect(clearedCredentials == nil)
    }
}
