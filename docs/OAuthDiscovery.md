# OAuth Discovery Implementation

This document describes the OAuth Discovery implementation in SwiftAgentKit, which provides comprehensive support for RFC 9728 (Protected Resource Metadata) and RFC 8414 (Authorization Server Metadata Discovery) as required by the MCP Auth specification.

## Overview

The OAuth Discovery system implements the complete authentication flow described in the MCP Auth specification, including:

- **Protected Resource Metadata Discovery** (RFC 9728)
- **WWW-Authenticate Header Parsing** for resource metadata URLs
- **Well-Known URI Probing** for `/.well-known/oauth-protected-resource` endpoints
- **Authorization Server Metadata Discovery** (RFC 8414)
- **OpenID Connect Discovery 1.0** support
- **OAuth 2.1 Authorization Flow** with PKCE

## Architecture

The OAuth Discovery system consists of several key components:

### Core Components

1. **ProtectedResourceMetadata** - Represents protected resource metadata as per RFC 9728
2. **OAuthServerMetadata** - Enhanced OAuth server metadata with discovery support
3. **OAuthDiscoveryManager** - Orchestrates the complete discovery process
4. **OAuthDiscoveryAuthProvider** - Authentication provider that uses discovery
5. **WWWAuthenticateParser** - Parses WWW-Authenticate headers for OAuth challenges

### Discovery Flow

The discovery process follows this sequence:

1. **Unauthenticated Request** - Make request to resource server
2. **401 Response Handling** - Parse WWW-Authenticate header
3. **Protected Resource Discovery** - Extract resource metadata
4. **Authorization Server Discovery** - Discover authorization server metadata
5. **OAuth Flow** - Perform OAuth 2.1 authorization with PKCE

## Usage

### Basic Usage with MCP Client

```swift
import SwiftAgentKit
import SwiftAgentKitMCP

// Create OAuth Discovery authentication provider
let authProvider = OAuthDiscoveryAuthProvider(
    resourceServerURL: URL(string: "https://mcp.example.com")!,
    clientId: "your-client-id",
    clientSecret: "your-client-secret", // Optional for public clients
    scope: "openid profile email",
    redirectURI: URL(string: "https://your-app.com/callback")!,
    resourceType: "mcp"
)

// Create MCP client with OAuth Discovery
let mcpClient = MCPClient(name: "MyMCPClient", version: "1.0")

// Connect to remote MCP server
try await mcpClient.connectToRemoteServer(
    serverURL: URL(string: "https://mcp.example.com")!,
    authProvider: authProvider
)

// Use MCP client normally - authentication is handled automatically
let tools = try await mcpClient.getTools()
```

### Manual Discovery Process

```swift
import SwiftAgentKit

// Create discovery manager
let discoveryManager = OAuthDiscoveryManager()

// Discover authorization server metadata
let authServerMetadata = try await discoveryManager.discoverAuthorizationServerMetadata(
    resourceServerURL: URL(string: "https://mcp.example.com")!,
    resourceType: "mcp",
    preConfiguredAuthServerURL: nil // Optional pre-configured URL
)

// Validate PKCE support
try authServerMetadata.validatePKCESupport()

// Check supported grant types
let supportsAuthCode = authServerMetadata.supportsAuthorizationCodeGrant()
let supportsPublicClient = authServerMetadata.supportsPublicClientAuthentication()
```

### WWW-Authenticate Header Parsing

```swift
import SwiftAgentKit

// Parse WWW-Authenticate header
let headerValue = "Bearer realm=\"mcp-server\", resource_metadata=\"https://mcp.example.com/.well-known/oauth-protected-resource/mcp\""
let parameters = WWWAuthenticateParser.parseWWWAuthenticateHeader(headerValue)

if let resourceMetadataURL = parameters["resource_metadata"] {
    print("Found resource metadata URL: \(resourceMetadataURL)")
}
```

### Protected Resource Metadata Discovery

```swift
import SwiftAgentKit

// Create protected resource metadata client
let protectedResourceClient = ProtectedResourceMetadataClient()

// Discover from WWW-Authenticate header
let challenge = AuthenticationChallenge(
    statusCode: 401,
    headers: ["WWW-Authenticate": "Bearer realm=\"mcp\", resource_metadata=\"https://mcp.example.com/.well-known/oauth-protected-resource/mcp\""],
    body: nil,
    serverInfo: "https://mcp.example.com"
)

let metadata = try await protectedResourceClient.discoverFromWWWAuthenticateHeader(challenge)

// Discover from well-known URI
let metadata2 = try await protectedResourceClient.discoverFromWellKnownURI(
    baseURL: URL(string: "https://mcp.example.com")!,
    resourceType: "mcp"
)
```

## Configuration

### Authentication Factory Integration

The OAuth Discovery provider can be created through the AuthenticationFactory:

```swift
import SwiftAgentKit

let config = JSON.object([
    "resourceServerURL": .string("https://mcp.example.com"),
    "clientId": .string("your-client-id"),
    "clientSecret": .string("your-client-secret"),
    "scope": .string("openid profile email"),
    "redirectURI": .string("https://your-app.com/callback"),
    "resourceType": .string("mcp"),
    "useOAuthDiscovery": .boolean(true),
    "preConfiguredAuthServerURL": .string("https://auth.example.com") // Optional
])

let authProvider = try AuthenticationFactory.createAuthProvider(authType: "oauth", config: config)
```

### Environment Variable Configuration

You can also configure OAuth Discovery through environment variables:

```bash
# Required
export MCP_SERVER_OAUTH_DISCOVERY_RESOURCE_SERVER_URL="https://mcp.example.com"
export MCP_SERVER_OAUTH_DISCOVERY_CLIENT_ID="your-client-id"
export MCP_SERVER_OAUTH_DISCOVERY_REDIRECT_URI="https://your-app.com/callback"

# Optional
export MCP_SERVER_OAUTH_DISCOVERY_CLIENT_SECRET="your-client-secret"
export MCP_SERVER_OAUTH_DISCOVERY_SCOPE="openid profile email"
export MCP_SERVER_OAUTH_DISCOVERY_RESOURCE_TYPE="mcp"
export MCP_SERVER_OAUTH_DISCOVERY_PRE_CONFIGURED_AUTH_SERVER_URL="https://auth.example.com"
```

## Discovery Strategies

The OAuth Discovery system implements multiple discovery strategies with fallback mechanisms:

### 1. WWW-Authenticate Header Discovery

When a client receives a 401 response, the system parses the WWW-Authenticate header to extract the `resource_metadata` parameter:

```
WWW-Authenticate: Bearer realm="mcp-server", resource_metadata="https://mcp.example.com/.well-known/oauth-protected-resource/mcp"
```

### 2. Well-Known URI Probing

If no resource metadata is found in the header, the system probes well-known URIs in this order:

1. `/.well-known/oauth-protected-resource/{resourceType}` (e.g., `/.well-known/oauth-protected-resource/mcp`)
2. `/.well-known/oauth-protected-resource` (root path)

### 3. Authorization Server Discovery

Once protected resource metadata is discovered, the system discovers the authorization server metadata using:

1. **OpenID Connect Discovery** (`.well-known/openid_configuration`) - Primary method
2. **OAuth 2.0 Authorization Server Metadata** (`.well-known/oauth-authorization-server`) - Fallback

## Security Features

### PKCE (Proof Key for Code Exchange)

The implementation enforces PKCE as required by OAuth 2.1 and MCP specification:

- **S256 Code Challenge Method** - Mandatory support
- **Automatic PKCE Pair Generation** - Secure code verifier and challenge generation
- **Server Validation** - Verifies authorization server supports PKCE

### Token Management

- **Automatic Token Refresh** - Handles token expiration transparently
- **Secure Token Storage** - Tokens are stored securely in memory
- **Token Validation** - Validates token expiration before use

### Discovery Security

- **HTTPS-Only Discovery** - All discovery endpoints must use HTTPS
- **Metadata Validation** - Validates discovered metadata for completeness
- **Fallback Strategies** - Multiple discovery methods for reliability

## Error Handling

The system provides comprehensive error handling for all discovery phases:

### Discovery Errors

```swift
enum OAuthDiscoveryError: LocalizedError {
    case networkError(String)
    case invalidResponse(String)
    case httpError(Int, String)
    case noAuthenticationRequired(String)
    case protectedResourceMetadataNotFound(String)
    case authorizationServerDiscoveryFailed(String)
    case invalidConfiguration(String)
}
```

### Protected Resource Metadata Errors

```swift
enum ProtectedResourceMetadataError: LocalizedError {
    case discoveryFailed(String)
    case invalidResponse(String)
    case httpError(Int, String)
    case pkceNotSupported(String)
    case invalidURL(String)
    case noAuthorizationServerURL
}
```

### OAuth Server Metadata Errors

```swift
enum OAuthMetadataError: LocalizedError {
    case discoveryFailed(String)
    case invalidResponse(String)
    case httpError(Int, String)
    case pkceNotSupported(String)
    case invalidIssuerURL(String)
}
```

## Testing

The implementation includes comprehensive tests covering:

- **Protected Resource Metadata Parsing** - JSON serialization/deserialization
- **WWW-Authenticate Header Parsing** - Various header formats and edge cases
- **Discovery Manager** - Complete discovery flow simulation
- **OAuth Discovery Auth Provider** - Authentication provider functionality
- **Error Handling** - All error conditions and edge cases

### Running Tests

```bash
swift test
```

## Compliance

The implementation is compliant with:

- **RFC 9728** - OAuth 2.0 Protected Resource Metadata Discovery
- **RFC 8414** - OAuth 2.0 Authorization Server Metadata
- **RFC 7636** - Proof Key for Code Exchange (PKCE)
- **OpenID Connect Discovery 1.0** - OpenID Connect Discovery specification
- **OAuth 2.1** - OAuth 2.1 security best practices
- **MCP Auth Specification** - Model Context Protocol authentication requirements

## Examples

See the `Examples/OAuthDiscoveryExample/` directory for comprehensive examples demonstrating:

- Manual discovery process
- OAuth Discovery authentication provider usage
- MCP client integration with OAuth Discovery
- Configuration options and error handling

## Migration Guide

### From Manual OAuth Configuration

If you're currently using manual OAuth configuration, you can migrate to OAuth Discovery:

**Before (Manual Configuration):**
```swift
let authProvider = PKCEOAuthAuthProvider(config: PKCEOAuthConfig(
    issuerURL: URL(string: "https://auth.example.com")!,
    clientId: "your-client-id",
    // ... other manual configuration
))
```

**After (OAuth Discovery):**
```swift
let authProvider = OAuthDiscoveryAuthProvider(
    resourceServerURL: URL(string: "https://mcp.example.com")!,
    clientId: "your-client-id",
    redirectURI: URL(string: "https://your-app.com/callback")!,
    preConfiguredAuthServerURL: URL(string: "https://auth.example.com") // Optional fallback
)
```

The OAuth Discovery approach eliminates the need to manually configure authorization server endpoints, as they are discovered automatically from the resource server.

## Troubleshooting

### Common Issues

1. **Discovery Fails** - Check that the resource server supports OAuth Discovery and returns proper WWW-Authenticate headers
2. **PKCE Not Supported** - Ensure the authorization server supports the S256 code challenge method
3. **Network Errors** - Verify network connectivity and HTTPS certificate validity
4. **Invalid Redirect URI** - Ensure the redirect URI matches the one registered with the authorization server

### Debug Logging

Enable debug logging to troubleshoot discovery issues:

```swift
import Logging

// Configure detailed logging
LoggingSystem.bootstrap { label in
    StreamLogHandler.standardOutput(label: label)
}

let logger = Logger(label: "OAuthDiscovery")
logger.logLevel = .debug
```

## Future Enhancements

Planned enhancements include:

- **Caching** - Cache discovered metadata to reduce discovery overhead
- **Retry Logic** - Enhanced retry mechanisms for network failures
- **Metrics** - Discovery performance and success rate metrics
- **Custom Discovery** - Support for custom discovery endpoints and protocols
