# PKCE OAuth Authentication for MCP Clients

This document describes the implementation of PKCE (Proof Key for Code Exchange) OAuth authentication for MCP clients, as required by the MCP specification.

## Overview

The MCP specification mandates that MCP clients must implement PKCE according to OAuth 2.1 Section 7.5.2 to prevent authorization code interception and injection attacks. This implementation provides a complete PKCE OAuth solution that meets all MCP requirements.

## Key Features

- **RFC 7636 Compliant**: Implements PKCE according to RFC 7636
- **OAuth 2.1 Compliant**: Uses S256 code challenge method as required
- **MCP Specification Compliant**: Validates PKCE support before proceeding
- **Authorization Server Discovery**: Supports both OAuth 2.0 and OpenID Connect Discovery
- **Public and Confidential Clients**: Supports both client types
- **Environment Variable Configuration**: Easy configuration via environment variables
- **MCP Integration**: Seamlessly integrates with MCP configuration system

## Components

### 1. PKCE Utilities (`PKCEUtilities.swift`)

Provides core PKCE functionality:

```swift
// Generate PKCE code verifier and challenge pair
let pkcePair = try PKCEUtilities.generatePKCEPair()

// Validate code verifier against challenge
let isValid = PKCEUtilities.validateCodeVerifier(codeVerifier, against: codeChallenge)
```

**Features:**
- Generates cryptographically secure code verifiers (43-128 characters)
- Creates S256 code challenges using SHA256 + base64url encoding
- Validates PKCE pairs for correctness

### 2. OAuth Server Metadata (`OAuthServerMetadata.swift`)

Handles OAuth server metadata discovery and validation:

```swift
// Discover OAuth server metadata
let metadataClient = OAuthServerMetadataClient()
let metadata = try await metadataClient.discoverOAuthServerMetadata(issuerURL: issuerURL)

// Validate PKCE support as required by MCP spec
let pkceSupported = try metadata.validatePKCESupport()
```

**Features:**
- OAuth 2.0 Authorization Server Metadata (RFC 8414)
- OpenID Connect Provider Metadata support
- PKCE support validation
- Grant type and authentication method validation

### 3. PKCE OAuth Authentication Provider (`PKCEOAuthAuthProvider.swift`)

Main authentication provider implementing the PKCE OAuth flow:

```swift
// Create PKCE OAuth configuration
let config = try PKCEOAuthConfig(
    issuerURL: URL(string: "https://auth.example.com")!,
    clientId: "your_client_id",
    redirectURI: URL(string: "https://app.example.com/callback")!
)

// Create authentication provider
let authProvider = PKCEOAuthAuthProvider(config: config)

// Start authorization flow
let authURL = try await authProvider.startAuthorizationFlow()

// Complete authorization flow with code
try await authProvider.completeAuthorizationFlow(authorizationCode: code)
```

**Features:**
- Authorization code flow with PKCE
- Automatic token refresh
- Server metadata discovery
- Support for both public and confidential clients
- State parameter for CSRF protection

### 4. Authentication Factory Integration (`AuthenticationFactory.swift`)

Extended to support PKCE OAuth configuration:

```swift
// Create from configuration
let provider = try AuthenticationFactory.createAuthProvider(
    authType: "oauth", 
    config: pkceConfigJSON
)

// Create from environment variables
let provider = AuthenticationFactory.createAuthProviderFromEnvironment(serverName: "myserver")
```

## Configuration

### JSON Configuration

```json
{
  "authType": "oauth",
  "authConfig": {
    "issuerURL": "https://auth.example.com",
    "clientId": "your_client_id",
    "clientSecret": "your_client_secret",
    "scope": "openid profile email",
    "redirectURI": "https://app.example.com/callback",
    "usePKCE": true,
    "useOpenIDConnectDiscovery": true,
    "authorizationEndpoint": "https://custom.example.com/oauth/authorize",
    "tokenEndpoint": "https://custom.example.com/oauth/token"
  }
}
```

### Environment Variables

```bash
# Required
SERVERNAME_PKCE_OAUTH_ISSUER_URL=https://auth.example.com
SERVERNAME_PKCE_OAUTH_CLIENT_ID=your_client_id
SERVERNAME_PKCE_OAUTH_REDIRECT_URI=https://app.example.com/callback

# Optional
SERVERNAME_PKCE_OAUTH_CLIENT_SECRET=your_client_secret
SERVERNAME_PKCE_OAUTH_SCOPE=openid profile
SERVERNAME_PKCE_OAUTH_AUTHORIZATION_ENDPOINT=https://custom.example.com/oauth/authorize
SERVERNAME_PKCE_OAUTH_TOKEN_ENDPOINT=https://custom.example.com/oauth/token
SERVERNAME_PKCE_OAUTH_USE_OIDC_DISCOVERY=true
```

### MCP Configuration

```json
{
  "remoteServers": {
    "oauth-server": {
      "url": "https://mcp.example.com",
      "authType": "oauth",
      "authConfig": {
        "issuerURL": "https://auth.example.com",
        "clientId": "mcp_client_id",
        "redirectURI": "https://mcp-app.example.com/callback",
        "usePKCE": true
      }
    }
  }
}
```

## MCP Specification Compliance

This implementation fully complies with the MCP specification requirements:

### 1. PKCE Implementation
- ✅ Implements PKCE according to OAuth 2.1 Section 7.5.2
- ✅ Uses S256 code challenge method (OAuth 2.1 Section 4.1.1)
- ✅ Generates cryptographically secure code verifiers

### 2. PKCE Support Validation
- ✅ Verifies `code_challenge_methods_supported` field presence
- ✅ Validates S256 method support
- ✅ Refuses to proceed if PKCE not supported

### 3. Authorization Server Discovery
- ✅ Supports OAuth 2.0 Authorization Server Metadata
- ✅ Supports OpenID Connect Discovery
- ✅ Validates PKCE support from server metadata

### 4. Security Features
- ✅ State parameter for CSRF protection
- ✅ Secure code verifier generation
- ✅ Proper base64url encoding
- ✅ SHA256 hash for code challenges

## Usage Examples

### Basic PKCE OAuth Flow

```swift
import SwiftAgentKit

// 1. Create PKCE OAuth configuration
let config = try PKCEOAuthConfig(
    issuerURL: URL(string: "https://auth.example.com")!,
    clientId: "your_client_id",
    redirectURI: URL(string: "https://app.example.com/callback")!
)

// 2. Create authentication provider
let authProvider = PKCEOAuthAuthProvider(config: config)

// 3. Start authorization flow
let authURL = try await authProvider.startAuthorizationFlow()
print("Visit: \(authURL)")

// 4. After user authorization, complete the flow
try await authProvider.completeAuthorizationFlow(authorizationCode: "auth_code")

// 5. Use authentication headers
let headers = try await authProvider.authenticationHeaders()
```

### MCP Client Integration

```swift
// Create MCP client with PKCE OAuth
let client = MCPClient(name: "oauth-client", version: "1.0")

// Create PKCE OAuth provider
let authProvider = PKCEOAuthAuthProvider(config: pkceConfig)

// Connect to remote MCP server
try await client.connectToRemoteServer(
    serverURL: URL(string: "https://mcp.example.com")!,
    authProvider: authProvider
)
```

### Environment Variable Configuration

```swift
// Automatically create PKCE OAuth provider from environment
let authProvider = AuthenticationFactory.createAuthProviderFromEnvironment(
    serverName: "myserver"
)

// Use with MCP client
try await client.connectToRemoteServer(
    serverURL: serverURL,
    authProvider: authProvider
)
```

## Security Considerations

1. **Code Verifier Security**: Uses cryptographically secure random generation
2. **Code Challenge Method**: Always uses S256 (SHA256 + base64url)
3. **State Parameter**: Includes CSRF protection
4. **Server Validation**: Validates PKCE support before proceeding
5. **Token Security**: Proper token storage and refresh handling

## Error Handling

The implementation provides comprehensive error handling:

```swift
enum PKCEError: LocalizedError {
    case invalidCodeVerifierLength(Int)
    case invalidCodeVerifier(String)
    case generationFailed(String)
}

enum OAuthMetadataError: LocalizedError {
    case discoveryFailed(String)
    case invalidResponse(String)
    case httpError(Int, String)
    case pkceNotSupported(String)
    case invalidIssuerURL(String)
}
```

## Testing

Run the PKCE OAuth example:

```bash
swift run pkce_oauth_example
```

Run the test suite:

```bash
swift test --filter PKCEUtilitiesTests
swift test --filter OAuthServerMetadataTests
swift test --filter PKCEOAuthAuthProviderTests
```

## Dependencies

- **Swift CryptoKit**: For SHA256 hashing
- **Swift Foundation**: For URL handling and networking
- **Swift Logging**: For logging support
- **EasyJSON**: For JSON configuration handling

## References

- [RFC 7636 - Proof Key for Code Exchange (PKCE)](https://tools.ietf.org/html/rfc7636)
- [OAuth 2.1 Security Best Current Practice](https://tools.ietf.org/html/draft-ietf-oauth-security-topics)
- [RFC 8414 - OAuth 2.0 Authorization Server Metadata](https://tools.ietf.org/html/rfc8414)
- [OpenID Connect Discovery 1.0](https://openid.net/specs/openid-connect-discovery-1_0.html)
- [MCP Specification](https://spec.modelcontextprotocol.io/)
