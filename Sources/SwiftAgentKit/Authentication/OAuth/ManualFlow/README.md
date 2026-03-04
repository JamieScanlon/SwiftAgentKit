# Manual OAuth Flow

When an OAuth provider requires the user to sign in in a browser (authorization code + PKCE), SwiftAgentKit throws **`OAuthManualFlowRequired`** with metadata (authorization endpoint, token endpoint, redirect URI, scope, resource URI). The types in this folder implement the **manual flow**: open the auth URL, run a local callback server to receive the redirect, exchange the code for tokens, and store them.

## Overview

| Type | Role |
|------|------|
| **OAuthAuthenticator** | Runs the manual flow: builds auth URL from `OAuthManualFlowRequired`, opens it in the browser, runs callback server, exchanges code for tokens using `PKCEUtilities`. Optional callback receiver, token exchanger, and URL opener. |
| **OAuthCallbackReceiver** | Protocol for receiving the redirect (authorization code). |
| **OAuthCallbackServer** | Local HTTP server that catches the OAuth redirect; conforms to `OAuthCallbackReceiver`. Uses the Network framework. |
| **OAuthTokenExchanger** | Protocol for exchanging the code for tokens at the token endpoint. |
| **DefaultOAuthTokenExchanger** | Default implementation (URLSession + JSON/form parsing). |
| **OAuthTokenStorage** | Protocol for storing/retrieving tokens (and optional config) per server. |
| **OAuthToken**, **OAuthTokenWithConfig** | Token and token+config value types. |
| **KeychainTokenStorage** | Keychain-backed storage (secure, persists across runs). |
| **InMemoryTokenStorage** | In-memory only (tests or when keychain is unavailable). |
| **RobustTokenStorage** | Prefers Keychain; falls back to in-memory if Keychain fails. |
| **OAuthError**, **KeychainError** | Error types for manual flow and keychain operations. |

## Completing the flow

1. Catch `OAuthManualFlowRequired` from your MCP (or other) client when it needs user login.
2. Call `OAuthAuthenticator.completeManualOAuthFlow(oauthFlowError:clientId:clientSecret:)`. The authenticator uses `PKCEUtilities` for PKCE, opens the auth URL (e.g. in the default browser on macOS), runs the callback server, and exchanges the code for tokens.
3. Build `OAuthTokenWithConfig` from the returned `OAuthToken` and your token endpoint/client id/secret/scope, then store it with your chosen `OAuthTokenStorage` (e.g. `RobustTokenStorage()`).
4. Retry the connection so the client can use the stored token (e.g. by creating a provider from the stored config or injecting the token into the next request).

## Customization

- **OAuthCallbackReceiver** — Use a custom implementation for a different callback mechanism or tests.
- **OAuthTokenExchanger** — Use a custom implementation for a different HTTP client or proxy.
- **URL opener** — Pass a closure to `OAuthAuthenticator` to control how the auth URL is opened (e.g. log it on non-macOS or in tests).

## Token storage

- **KeychainTokenStorage(service:logger:)** — Default `service` is `"SwiftAgentKit.OAuth"`. Supports `OAuthToken` and `OAuthTokenWithConfig`.
- **InMemoryTokenStorage** — No persistence; useful for tests.
- **RobustTokenStorage** — Tries Keychain first; on permission errors, falls back to in-memory so the app can continue without keychain access.
