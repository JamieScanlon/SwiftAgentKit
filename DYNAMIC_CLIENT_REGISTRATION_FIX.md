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

### 1. OAuthDiscoveryAuthProvider.swift

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

### 2. DynamicClientRegistration.swift

Fixed the client registration request to include all required fields and proper JSON encoding:

```swift
// Added missing tokenEndpointAuthMethod field
public static func mcpClientRequest(
    redirectUris: [String],
    clientName: String? = nil,
    scope: String? = nil,
    additionalMetadata: [String: String]? = nil
) -> ClientRegistrationRequest {
    return ClientRegistrationRequest(
        redirectUris: redirectUris,
        applicationType: "native",
        clientName: clientName ?? "MCP Client",
        tokenEndpointAuthMethod: "none", // PKCE clients use "none" for token endpoint auth
        grantTypes: ["authorization_code", "refresh_token"],
        responseTypes: ["code"],
        scope: scope ?? "mcp",
        additionalMetadata: additionalMetadata
    )
}

// Added CodingKeys for proper snake_case JSON field names
enum CodingKeys: String, CodingKey {
    case redirectUris = "redirect_uris"
    case applicationType = "application_type"
    case clientName = "client_name"
    case tokenEndpointAuthMethod = "token_endpoint_auth_method"
    case grantTypes = "grant_types"
    case responseTypes = "response_types"
    // ... other fields
}
```

### 3. OAuth Flow Updates

Updated all OAuth flow methods to use the effective client ID:

```swift
// Use registered client ID if available, otherwise fall back to provided client ID
let effectiveClientId = registeredClientId ?? clientId
let effectiveClientSecret = registeredClientSecret ?? clientSecret
```

### 2. DynamicClientRegistration.swift

**Response Decoding Fix**: Added `CodingKeys` to handle Zapier's snake_case response format:

```swift
enum CodingKeys: String, CodingKey {
    case clientId = "client_id"
    case clientSecret = "client_secret"
    case clientIdIssuedAt = "client_id_issued_at"
    case clientSecretExpiresAt = "client_secret_expires_at"
    case redirectUris = "redirect_uris"
    case applicationType = "application_type"
    case clientUri = "client_uri"
    case contacts
    case clientName = "client_name"
    case logoUri = "logo_uri"
    case tosUri = "tos_uri"
    case policyUri = "policy_uri"
    case jwksUri = "jwks_uri"
    case jwks
    case tokenEndpointAuthMethod = "token_endpoint_auth_method"
    case grantTypes = "grant_types"
    case responseTypes = "response_types"
    case scope
    case additionalMetadata
}
```

**Zapier Response Format**:
```json
{
  "client_id": "nla-YJgutuF1UAlgbomkQlGZOfTySeRITqiht3l9",
  "client_id_issued_at": 1758671007,
  "client_name": "SwiftAgentKit MCP Client",
  "redirect_uris": ["http://localhost:8080/oauth/callback"],
  "grant_types": ["authorization_code", "refresh_token"],
  "token_endpoint_auth_method": "none",
  "response_types": ["code"],
  "scope": "profile email"
}
```

## How It Works Now

### For Zapier (with registration endpoint):

1. **Discovery**: ✅ OAuth server metadata discovered
2. **Registration Check**: ✅ `registration_endpoint` found: `https://mcp.zapier.com/register`
3. **Dynamic Registration**: ✅ POST to registration endpoint with MCP-optimized client metadata
4. **Get Valid Client ID**: ✅ Receive registered client ID from Zapier (with proper snake_case → camelCase decoding)
5. **OAuth Flow**: ✅ Use registered client ID for authorization and token exchange

### For Other Servers (without registration endpoint):

1. **Discovery**: ✅ OAuth server metadata discovered
2. **Registration Check**: ✅ No `registration_endpoint` found
3. **Fallback**: ✅ Use provided client ID (`swiftagentkit-mcp-client`)
4. **OAuth Flow**: ✅ Use provided client ID for authorization and token exchange

## Configuration

Both the redirect URI and scope are now configurable through the MCP configuration file. You can specify them in the `authConfig` section:

```json
{
  "remoteServers": {
    "generic-mcp-server": {
      "url": "https://mcp.example.com/api/mcp",
      "authType": "OAuth",
      "authConfig": {
        "useDynamicClientRegistration": true,
        "redirectUris": ["http://localhost:8080/oauth/callback"],
        "clientName": "My MCP Client",
        "scope": "mcp"
      }
    },
    "zapier-server": {
      "url": "https://mcp.zapier.com/api/mcp/a/12345/mcp",
      "authType": "OAuth",
      "authConfig": {
        "useDynamicClientRegistration": true,
        "redirectUris": ["http://localhost:8080/oauth/callback"],
        "clientName": "SwiftAgentKit MCP Client",
        "scope": "profile email"
      }
    }
  }
}
```

**Configuration Options**:

- **redirectUris**: If not specified, defaults to `["http://localhost:8080/oauth/callback"]`
- **scope**: If not specified, the system will intelligently select the best scope based on what the server supports
- **Intelligent Scope Selection**: The system automatically discovers server-supported scopes and selects the most appropriate one:
  1. If you configure a scope and the server supports it, that scope is used
  2. If the configured scope isn't supported, the system uses intelligent scope selection:
     - **Exact Combined Scopes** (highest priority): `"mcp"`, `"profile email"`, `"openid profile email"`
     - **Built Combined Scopes**: Automatically combines individual scopes:
       - `["profile", "email"]` → `"profile email"` (for Zapier)
       - `["openid", "profile", "email"]` → `"openid profile email"`
       - `["openid", "profile"]` → `"openid profile"`
       - `["openid", "email"]` → `"openid email"`
     - **Individual Scopes** (fallback): `"openid"`, `"profile"`, `"email"`
  3. If no preferred scope is available, the first server-supported scope is used
  4. If the server doesn't specify supported scopes, defaults to `"mcp"`

**Common Server Scopes**:
- Generic MCP servers: `"mcp"`
- Zapier: `"profile email"`
- OpenID Connect servers: `"openid profile email"`
- Custom servers: Check their documentation for required scopes

You can specify multiple redirect URIs if your application supports multiple callback schemes:

```json
"redirectUris": [
  "http://localhost:8080/oauth/callback",
  "https://myapp.com/oauth/callback",
  "com.myapp://oauth-callback"
]
```

## Testing

Added comprehensive tests to verify:

- ✅ Dynamic client registration detection
- ✅ Fallback to provided client ID when registration not supported
- ✅ MCP-optimized registration request creation
- ✅ Integration with existing OAuth discovery flow
- ✅ Configurable redirect URI support
- ✅ Zapier response format decoding (snake_case → camelCase mapping)
- ✅ Intelligent scope selection based on server capabilities

### Enhanced Logging

The system now includes comprehensive logging to help debug OAuth flow issues:

**Registration Logging**:
```
Dynamic client registration selected scope: 'profile email' (configured: 'mcp')
Server supported scopes: ["profile", "email"]
Registration Summary:
  - Registered Client ID: nla-ABC123...
  - Registration Scope: 'profile email'
  - Server Supported Scopes: ["profile", "email"]
  - This scope will be used consistently in OAuth flow
```

**OAuth Flow Logging**:
```
OAuth flow using registered client ID: nla-ABC123...
OAuth flow selected scope: 'profile email' (configured: 'mcp')
Added scope parameter to authorization URL: 'profile email'
Authorization URL breakdown:
  - Client ID: nla-ABC123...
  - Scope: 'profile email'
  - Redirect URI: http://localhost:8080/oauth/callback
  - Code Challenge: ABC123...
  - Resource: https://mcp.zapier.com/api/mcp/a/12345/mcp
```

**Token Exchange Logging**:
```
Token exchange using registered client ID: nla-ABC123...
Token exchange using scope: 'profile email' (same as registration)
🔍 SCOPE CONSISTENCY CHECK:
  - Using registered client ID: nla-ABC123...
  - Token exchange scope: 'profile email'
  - This scope MUST match the registration scope exactly
Added scope parameter to token exchange request: 'profile email'
⚠️  If token exchange fails with 'invalid_scope', try removing scope parameter from token exchange
Token exchange request body: grant_type=authorization_code&code=ABC123&redirect_uri=http://localhost:8080/oauth/callback&client_id=nla-ABC123&code_verifier=ABC123&scope=profile%20email&resource=https://mcp.zapier.com/api/mcp/a/12345/mcp
Token exchange request URL: https://mcp.zapier.com/token
Token exchange request headers: ["Content-Type": "application/x-www-form-urlencoded"]
```

**Token Refresh Logging**:
```
Token refresh using registered client ID: nla-ABC123...
Token refresh using scope: 'profile email' (same as registration)
Added scope parameter to token refresh request: 'profile email'
```

This logging helps ensure:
- ✅ Scope consistency across all OAuth steps
- ✅ Proper client ID usage (registered vs provided)
- ✅ Complete visibility into OAuth parameters
- ✅ Easy debugging of scope-related issues
- ✅ Complete token exchange request visibility
- ✅ Clear error messages with request details

### Common OAuth Issues and Solutions

**Issue**: Token exchange fails with `invalid_scope` error
**Possible Causes**:
1. **Scope Parameter Issue**: Some OAuth servers don't expect scope in token exchange if it matches the authorization request
2. **Scope Format Mismatch**: URL encoding differences between authorization and token exchange
3. **Client Registration Mismatch**: Registered scope doesn't match authorization scope

**Debugging Steps**:
1. Check the token exchange request body in the logs
2. Verify the scope parameter matches exactly what was registered
3. Try removing the scope parameter from token exchange (some servers don't require it)
4. Ensure the client_id matches the registered client ID exactly

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

## Root Cause of the "invalid_client_metadata" Error

The original implementation was sending invalid client metadata to Zapier because:

1. **Missing `token_endpoint_auth_method` field**: Required for PKCE clients (should be "none")
2. **Wrong JSON field names**: Using camelCase instead of snake_case as required by OAuth 2.0 Dynamic Client Registration spec

## Fixed Client Metadata

The registration request now includes all required fields with proper JSON encoding:

```json
{
  "application_type" : "native",
  "client_name" : "SwiftAgentKit MCP Client",
  "grant_types" : [
    "authorization_code",
    "refresh_token"
  ],
  "redirect_uris" : [
    "https://example.com/oauth/callback"
  ],
  "response_types" : [
    "code"
  ],
  "scope" : "mcp",
  "token_endpoint_auth_method" : "none"
}
```

## Files Modified

- `Sources/SwiftAgentKit/Authentication/OAuthDiscoveryAuthProvider.swift` - Main implementation
- `Sources/SwiftAgentKit/Authentication/DynamicClientRegistration.swift` - Fixed metadata and JSON encoding
- `Sources/SwiftAgentKit/Authentication/DynamicClientRegistrationClient.swift` - Enhanced error logging
- `Tests/SwiftAgentKitMCPTests/OAuth DiscoveryFlowTests.swift` - Added tests
- `Examples/DynamicClientRegistrationExample/main.swift` - Example usage

This fix resolves the issue where SwiftAgentKit was not performing dynamic client registration with Zapier, allowing proper authentication with servers that support OAuth 2.0 Dynamic Client Registration.
