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

## Using an existing HTTP server (e.g. Vapor) for the callback

If you already run an HTTP server (e.g. Vapor on port 8080), you can add a route (e.g. `/auth/callback`) and use it as the OAuth redirect target instead of starting the built-in `OAuthCallbackServer`.

1. **Configure your OAuth app** so the redirect URI is your route (e.g. `http://localhost:8080/auth/callback`). Your MCP/OAuth config must use that same redirect URI so the provider redirects to your server.

2. **Implement a callback receiver** that bridges your route to the manual flow. The receiver’s `waitForCallback(timeout:)` must suspend until the callback request arrives; when your route is hit, deliver the query parameters (e.g. `code`, `state`, `error`, `error_description`) into that receiver so it can return an `OAuthCallbackServer.CallbackResult`.

   Example (shared between the flow and your route):

   ```swift
   import SwiftAgentKit

   /// Receives the OAuth redirect via a callback you trigger from your own HTTP route.
   public final class ExternalServerOAuthCallbackReceiver: OAuthCallbackReceiver, @unchecked Sendable {
       private let lock = NSLock()
       private var continuation: CheckedContinuation<OAuthCallbackServer.CallbackResult, Error>?

       public init() {}

       public func waitForCallback(timeout: TimeInterval) async throws -> OAuthCallbackServer.CallbackResult {
           try await withCheckedThrowingContinuation { continuation in
               lock.lock()
               self.continuation = continuation
               lock.unlock()

               Task {
                   try await Task.sleep(for: .seconds(timeout))
                   lock.lock()
                   if let c = self.continuation {
                       self.continuation = nil
                       lock.unlock()
                       c.resume(throwing: OAuthError.networkError("OAuth callback timeout"))
                   } else {
                       lock.unlock()
                   }
               }
           }
       }

       /// Call this from your HTTP route (e.g. Vapor GET /auth/callback) with the query parameters from the redirect.
       public func deliver(authorizationCode: String?, state: String?, error: String?, errorDescription: String?) {
           let result = OAuthCallbackServer.CallbackResult(
               authorizationCode: authorizationCode,
               state: state,
               error: error,
               errorDescription: errorDescription
           )
           lock.lock()
           let c = continuation
           continuation = nil
           lock.unlock()
           c?.resume(returning: result)
       }
   }
   ```

3. **In your Vapor app**, register the callback route and use the same receiver instance:

   ```swift
   // One receiver per app (or per flow); share it with the OAuth setup.
   let oauthCallbackReceiver = ExternalServerOAuthCallbackReceiver()

   // When configuring routes (e.g. in configure.swift or routes):
   app.get("auth", "callback") { req -> EventLoopFuture<Response> in
       let code = req.query[String.self, at: "code"]
       let state = req.query[String.self, at: "state"]
       let error = req.query[String.self, at: "error"]
       let errorDescription = req.query[String.self, at: "error_description"]
       oauthCallbackReceiver.deliver(
           authorizationCode: code,
           state: state,
           error: error,
           errorDescription: errorDescription
       )
       let body = (error == nil)
           ? "Authentication successful. You can close this window."
           : "Authentication failed: \(errorDescription ?? error ?? "unknown")"
       return req.eventLoop.makeSucceededFuture(
           Response(status: .ok, body: .init(string: body))
       )
   }
   ```

4. **Pass the receiver into the OAuth handler** so no extra callback server is started. You can do this in two ways (same outcome for the callback):

   **Convenience (custom callback only):** Use the `callbackReceiver` parameter. Best when you only need to plug in your own callback and are fine with default token exchange and URL opening.

   ```swift
   let oauthHandler = MCPOAuthHandler(callbackReceiver: oauthCallbackReceiver)
   ```

   **Full control (custom callback and/or token exchanger and/or URL opener):** Use the `authenticator` parameter with a fully configured ``OAuthAuthenticator``. Best when you need to customize more than just where the redirect is received.

   ```swift
   let authenticator = OAuthAuthenticator(
       callbackReceiver: oauthCallbackReceiver,
       tokenExchanger: nil,  // or your custom exchanger
       urlOpener: nil       // or your custom opener
   )
   let oauthHandler = MCPOAuthHandler(authenticator: authenticator)
   ```

   In both cases, when OAuth is required the flow opens the auth URL and waits on your receiver’s `waitForCallback`; your route receives the redirect and calls `deliver(...)`, completing the flow. Ensure the redirect URI in your OAuth/MCP config matches your route (e.g. `http://localhost:8080/auth/callback`). Only one OAuth flow should be waiting at a time on a given receiver instance.

## Customization

- **OAuthCallbackReceiver** — Use a custom implementation for a different callback mechanism or tests (e.g. the Vapor example above).
- **OAuthTokenExchanger** — Use a custom implementation for a different HTTP client or proxy.
- **URL opener** — Pass a closure to `OAuthAuthenticator` to control how the auth URL is opened (e.g. log it on non-macOS or in tests).

## Token storage

- **KeychainTokenStorage(service:logger:)** — Default `service` is `"SwiftAgentKit.OAuth"`. Supports `OAuthToken` and `OAuthTokenWithConfig`.
- **InMemoryTokenStorage** — No persistence; useful for tests.
- **RobustTokenStorage** — Tries Keychain first; on permission errors, falls back to in-memory so the app can continue without keychain access.
