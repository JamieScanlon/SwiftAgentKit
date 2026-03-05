# Authentication in SwiftAgentKit

SwiftAgentKit uses a **provider-based** authentication model: remote services (e.g. MCP servers, APIs) are accessed through a single interface—`AuthenticationProvider`—while the actual scheme (Bearer, API Key, Basic, OAuth) is chosen by configuration and created by `AuthenticationFactory`.

## Core concepts

### `AuthenticationProvider`

All auth in SwiftAgentKit goes through the `AuthenticationProvider` protocol. A provider:

- **Declares its scheme** via `scheme: AuthenticationScheme` (e.g. `.bearer`, `.apiKey`, `.oauth`).
- **Supplies headers** with `authenticationHeaders() async throws -> [String: String]` for outgoing HTTP requests.
- **Handles challenges** with `handleAuthenticationChallenge(_:)` when the server returns 401/403 or similar, so the provider can refresh tokens or re-authenticate.
- **Reports validity** with `isAuthenticationValid()` and **cleans up** with `cleanup()` when the session ends.

Consumers (e.g. `RemoteTransport`, MCP client) never need to know whether they’re using a token, API key, or OAuth; they just call these methods.

### `AuthenticationScheme`

Supported schemes:

- **Simple:** `bearer`, `basic`, `apiKey` — credentials are fixed or stored; no interactive flow.
- **OAuth:** `oauth` — multiple implementations (direct tokens, discovery, PKCE, dynamic client registration) for different deployment and security needs.

Custom schemes are representable via `AuthenticationScheme.custom(String)` but are not instantiated by the factory.

### `AuthenticationFactory`

The factory is the single place to **create** providers:

- **From config:** `createAuthProvider(authType:config:)` or `createAuthProvider(authType:config:serverURL:)`.  
  `authType` is the scheme name (e.g. `"bearer"`, `"oauth"`); `config` is a JSON object with scheme-specific keys. For OAuth with a `serverURL`, the factory can inject resource URLs (RFC 8707) when required.
- **From environment:** `createAuthProviderFromEnvironment(serverName:)`.  
  Uses a prefix like `SERVERNAME_` and looks for variables such as `SERVERNAME_TOKEN`, `SERVERNAME_API_KEY`, `SERVERNAME_PKCE_OAUTH_*`, etc., and returns a provider if a matching set is found.

Consumers typically use either config (e.g. from MCP config files) or environment, not both for the same server; the factory does not merge them.

## How authentication is used

1. **Creating a provider**  
   At setup (e.g. when connecting to a remote MCP server), the app or framework calls `AuthenticationFactory.createAuthProvider(...)` (or `createAuthProviderFromEnvironment`) and stores the resulting `any AuthenticationProvider`.

2. **Sending requests**  
   Before each HTTP request, the client calls `await provider.authenticationHeaders()` and adds the returned headers to the request.

3. **Handling 401/403**  
   If the server responds with an auth challenge, the client builds an `AuthenticationChallenge` and calls `await provider.handleAuthenticationChallenge(challenge)`. If the provider can refresh or re-auth, it returns new headers to retry with; otherwise it throws.

4. **Shutdown**  
   When the connection or session ends, the client calls `await provider.cleanup()` so the provider can revoke or discard tokens and release resources.

OAuth providers may throw `OAuthManualFlowRequired` when user interaction (e.g. opening a browser) is required; the host application is responsible for handling that and, if applicable, feeding back tokens or codes into the provider or config.

When using OAuth Discovery (e.g. for remote MCP servers), the library may attempt **dynamic client registration (DCR)** if the auth server advertises a `registration_endpoint`. If the remote server config **already has a client ID** (top-level `clientID` or `clientId` in `authConfig`), the MCP client skips DCR and uses that client ID directly. That avoids DCR attempts against servers that do not support it (e.g. Todoist), preventing non-fatal errors such as "Server returned 200 but response was not valid DCR JSON".

## Folder structure

- **Root**  
  - `AuthenticationProvider.swift` — protocol, `AuthenticationScheme`, `AuthenticationChallenge`, `AuthenticationError`, `OAuthManualFlowRequired`.  
  - `AuthenticationFactory.swift` — creation from config and environment.

- **Simple/**  
  - **Providers/** — implementations for non-OAuth schemes:  
    - `APIKeyAuthProvider`, `BasicAuthProvider`, `BearerTokenAuthProvider`.

- **OAuth/**  
  - **Providers/** — OAuth implementations:  
    - `OAuthAuthProvider` (direct token/config), `OAuthDiscoveryAuthProvider`, `PKCEOAuthAuthProvider`, `DynamicClientRegistrationAuthProvider`.  
  - **Models/** — metadata and DCR types:  
    - `OAuthServerMetadata`, `ProtectedResourceMetadata`, `DynamicClientRegistration`.  
  - **Utilities/** — PKCE and resource indicators:  
    - `PKCEUtilities`, `ResourceIndicatorUtilities`.  
  - **Support/** — discovery and registration clients:  
    - `OAuthDiscoveryManager`, `DynamicClientRegistrationClient`.  
  - **ManualFlow/** — when the provider throws `OAuthManualFlowRequired`, use these to complete the flow in the app:  
    - `OAuthAuthenticator` (opens auth URL, runs callback server, exchanges code for tokens), `OAuthCallbackServer`, `OAuthTokenExchanger`, `OAuthTokenStorage` and implementations (Keychain, in-memory, robust fallback). See `OAuth/ManualFlow/README.md`.

Simple auth is “configure and use”; OAuth adds discovery, PKCE, and optional dynamic client registration, with the same `AuthenticationProvider` interface for callers.

## Summary

- **One interface:** `AuthenticationProvider` for all schemes.  
- **One factory:** `AuthenticationFactory` to create providers from config or environment.  
- **Same usage:** get headers, handle challenges, check validity, cleanup.  
- **Structure:** core types at the root; Simple and OAuth each have their own providers (and OAuth has models, utilities, and support types).

This keeps authentication scheme details and credential handling inside the Authentication module while the rest of SwiftAgentKit depends only on the protocol and the factory.
