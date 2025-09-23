# Dynamic Client Registration Fix

## Problem Summary

SwiftAgentKit was not performing dynamic client registration even when authorization servers (like Zapier) supported it. The system was using a hardcoded `swiftagentkit-mcp-client` instead of registering and obtaining a valid client ID.

## Root Cause

The `OAuthDiscoveryAuthProvider` was:
1. ✅ Correctly discovering OAuth server metadata (including `registration_endpoint`)
2. ❌ **Not checking if dynamic client registration was available**
3. ❌ **Not performing actual client registration**
4. ❌ **Using hardcoded client ID instead of registered one**

## Solution Implemented

Modified `OAuthDiscoveryAuthProvider` to:

1. **Check for registration endpoint**: After OAuth discovery, check if the server metadata contains a `registration_endpoint`
2. **Perform dynamic client registration**: If available, call the registration endpoint to get a valid client ID
3. **Use registered credentials**: Use the registered client ID and secret for the OAuth flow
4. **Fallback gracefully**: If registration fails or isn't supported, fall back to the provided client ID

## Key Changes

### OAuthDiscoveryAuthProvider.swift

```swift
// Added state for registered client credentials
private var registeredClientId: String?
private var registeredClientSecret: String?

// Modified authentication flow
private func ensureValidAuthentication() async throws {
    // ... existing discovery code ...
    
    // NEW: Check if dynamic client registration is needed and perform it
    try await ensureRegisteredClient()
    
    // ... existing OAuth flow code ...
}

// NEW: Ensure we have a registered client
private func ensureRegisteredClient() async throws {
    guard let metadata = oauthServerMetadata else {
        throw AuthenticationError.authenticationFailed("No OAuth server metadata available")
    }
    
    // If we already have a registered client ID, use it
    if let registeredClientId = registeredClientId {
        logger.info("Using existing registered client ID: \(registeredClientId)")
        return
    }
    
    // Check if the authorization server supports dynamic client registration
    guard let registrationEndpoint = metadata.registrationEndpoint else {
        logger.info("Authorization server does not support dynamic client registration, using provided client ID: \(clientId)")
        return
    }
    
    logger.info("Authorization server supports dynamic client registration at: \(registrationEndpoint)")
    
    // Perform dynamic client registration
    try await performDynamicClientRegistration(registrationEndpoint: registrationEndpoint, metadata: metadata)
}
```

### OAuth Flow Updates

Updated all OAuth flow methods to use the effective client ID:

```swift
// Use registered client ID if available, otherwise fall back to provided client ID
let effectiveClientId = registeredClientId ?? clientId
let effectiveClientSecret = registeredClientSecret ?? clientSecret
```

## How It Works Now

### For Zapier (with registration endpoint):

1. **Discovery**: ✅ OAuth server metadata discovered
2. **Registration Check**: ✅ `registration_endpoint` found: `https://mcp.zapier.com/register`
3. **Dynamic Registration**: ✅ POST to registration endpoint with MCP-optimized client metadata
4. **Get Valid Client ID**: ✅ Receive registered client ID from Zapier
5. **OAuth Flow**: ✅ Use registered client ID for authorization and token exchange

### For Other Servers (without registration endpoint):

1. **Discovery**: ✅ OAuth server metadata discovered
2. **Registration Check**: ✅ No `registration_endpoint` found
3. **Fallback**: ✅ Use provided client ID (`swiftagentkit-mcp-client`)
4. **OAuth Flow**: ✅ Use provided client ID for authorization and token exchange

## Testing

Added comprehensive tests to verify:

- ✅ Dynamic client registration detection
- ✅ Fallback to provided client ID when registration not supported
- ✅ MCP-optimized registration request creation
- ✅ Integration with existing OAuth discovery flow

## Example Usage

```swift
let authProvider = try OAuthDiscoveryAuthProvider(
    resourceServerURL: URL(string: "https://mcp.zapier.com/api/mcp/a/12345/mcp")!,
    clientId: "swiftagentkit-mcp-client", // Fallback client ID
    redirectURI: URL(string: "https://example.com/callback")!,
    scope: "mcp"
)

// This will now automatically:
// 1. Discover OAuth server metadata
// 2. Check for registration_endpoint
// 3. Perform dynamic client registration if supported
// 4. Use registered client_id for OAuth flow
let headers = try await authProvider.authenticationHeaders()
```

## Benefits

- ✅ **Automatic**: No configuration changes needed
- ✅ **Backward Compatible**: Still works with servers that don't support registration
- ✅ **Standards Compliant**: Follows RFC 7591 Dynamic Client Registration
- ✅ **MCP Optimized**: Registration requests are optimized for MCP clients
- ✅ **Robust**: Graceful fallback if registration fails

## Files Modified

- `Sources/SwiftAgentKit/Authentication/OAuthDiscoveryAuthProvider.swift` - Main implementation
- `Tests/SwiftAgentKitMCPTests/OAuth DiscoveryFlowTests.swift` - Added tests
- `Examples/DynamicClientRegistrationExample/main.swift` - Example usage

This fix resolves the issue where SwiftAgentKit was not performing dynamic client registration with Zapier, allowing proper authentication with servers that support OAuth 2.0 Dynamic Client Registration.
