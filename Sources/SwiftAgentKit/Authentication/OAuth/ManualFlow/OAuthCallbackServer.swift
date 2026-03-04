// OAuth Callback Server for Command Line Applications
// Handles OAuth callback redirects when running as a command line tool

import Foundation
import Logging
import Network
#if canImport(AppKit)
import AppKit
#endif

/// A type that can receive the OAuth redirect and return the authorization code (and optional state/error).
/// Implement this to use a custom callback server, test double, or other mechanism.
public protocol OAuthCallbackReceiver: Sendable {
    /// Waits for the provider to redirect the user back and returns the callback result.
    func waitForCallback(timeout: TimeInterval) async throws -> OAuthCallbackServer.CallbackResult
}

/// Simple HTTP server to handle OAuth callbacks for command line applications
public final class OAuthCallbackServer: OAuthCallbackReceiver, @unchecked Sendable {
    
    public struct CallbackResult: Sendable {
        public let authorizationCode: String?
        public let state: String?
        public let error: String?
        public let errorDescription: String?
        
        public init(authorizationCode: String?, state: String?, error: String?, errorDescription: String?) {
            self.authorizationCode = authorizationCode
            self.state = state
            self.error = error
            self.errorDescription = errorDescription
        }
        
        public var isSuccess: Bool {
            return authorizationCode != nil && error == nil
        }
    }
    
    private var listener: NWListener?
    private var continuation: CheckedContinuation<CallbackResult, Error>?
    private let port: UInt16
    private let callbackPath: String
    private let logger: Logger
    
    public init(port: UInt16 = 8080, callbackPath: String = "/oauth/callback", logger: Logger? = nil) {
        self.port = port
        self.callbackPath = callbackPath
        self.logger = logger ?? SwiftAgentKitLogging.logger(for: .authentication("OAuthCallbackServer"), metadata: ["port": .stringConvertible(port), "path": .string(callbackPath)])
    }
    
    /// Starts the callback server and waits for OAuth callback
    /// - Parameter timeout: Maximum time to wait for callback (default: 300 seconds)
    /// - Returns: OAuth callback result
    public func waitForCallback(timeout: TimeInterval = 300) async throws -> CallbackResult {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            
            Task {
                do {
                    try await startServer()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            
            // Set up timeout
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                if self.continuation != nil {
                    self.continuation?.resume(throwing: OAuthError.networkError("OAuth callback timeout"))
                    self.continuation = nil
                    await self.stopServer()
                }
            }
        }
    }
    
    private func startServer() async throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: port))
        
        listener?.newConnectionHandler = { [weak self] connection in
            Task {
                await self?.handleConnection(connection)
            }
        }
        
        listener?.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.logger.info("OAuth callback server listening", metadata: ["port": .stringConvertible(self.port), "callbackURL": .string("http://localhost:\(self.port)\(self.callbackPath)")])
            case .failed(let error):
                self.logger.error("OAuth callback server failed", metadata: ["error": .string(String(describing: error))])
                Task {
                    self.handleError(error)
                }
            default:
                break
            }
        }
        
        listener?.start(queue: .global())
    }
    
    private func handleConnection(_ connection: NWConnection) async {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveRequest(connection)
            case .failed(let error):
                self?.logger.error("OAuth callback connection failed", metadata: ["error": .string(String(describing: error))])
                connection.cancel()
            default:
                break
            }
        }
        
        connection.start(queue: .global())
    }
    
    private func receiveRequest(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            if let error = error {
                self?.logger.error("OAuth callback receive error", metadata: ["error": .string(String(describing: error))])
                connection.cancel()
                return
            }
            
            guard let data = data, !data.isEmpty else {
                if isComplete {
                    connection.cancel()
                }
                return
            }
            
            Task {
                self?.processRequest(data: data, connection: connection)
            }
        }
    }
    
    private func processRequest(data: Data, connection: NWConnection) {
        guard let requestString = String(data: data, encoding: .utf8) else {
            Task { await sendResponse(connection: connection, statusCode: 400, body: "Bad Request") }
            return
        }
        
        let lines = requestString.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            Task { await sendResponse(connection: connection, statusCode: 400, body: "Bad Request") }
            return
        }
        
        let components = firstLine.components(separatedBy: " ")
        guard components.count >= 2,
              components[0] == "GET",
              let url = URL(string: "http://localhost" + components[1]) else {
            Task { await sendResponse(connection: connection, statusCode: 400, body: "Bad Request") }
            return
        }
        
        // Check if this is our callback path
        guard url.path == callbackPath else {
            Task { await sendResponse(connection: connection, statusCode: 404, body: "Not Found") }
            return
        }
        
        // Parse query parameters
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let authCode = queryItems.first { $0.name == "code" }?.value
        let state = queryItems.first { $0.name == "state" }?.value
        let error = queryItems.first { $0.name == "error" }?.value
        let errorDescription = queryItems.first { $0.name == "error_description" }?.value
        
        let result = CallbackResult(
            authorizationCode: authCode,
            state: state,
            error: error,
            errorDescription: errorDescription
        )
        
        // Send success response
        let responseBody = result.isSuccess ?
            "✅ Authentication successful! You can close this window." :
            "❌ Authentication failed: \(error ?? "Unknown error")"
            
        Task { await sendResponse(connection: connection, statusCode: 200, body: responseBody) }
        
        // Resume the continuation
        continuation?.resume(returning: result)
        continuation = nil
        
        // Stop the server
        Task { await stopServer() }
    }
    
    private func sendResponse(connection: NWConnection, statusCode: Int, body: String) async {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>OAuth Callback</title>
            <style>
                body { 
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    min-height: 100vh;
                    margin: 0;
                    background: #f5f5f5;
                }
                .container {
                    background: white;
                    padding: 2rem;
                    border-radius: 8px;
                    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
                    text-align: center;
                    max-width: 400px;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>SwiftAgentKit</h1>
                <p>\(body)</p>
            </div>
        </body>
        </html>
        """
        
        let response = """
        HTTP/1.1 \(statusCode) OK\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(html.utf8.count)\r
        Connection: close\r
        \r
        \(html)
        """
        
        let responseData = response.data(using: .utf8)!
        
        connection.send(content: responseData, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.logger.error("OAuth callback send error", metadata: ["error": .string(String(describing: error))])
            }
            connection.cancel()
        })
    }
    
    private func handleError(_ error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
        Task { await stopServer() }
    }
    
    private func stopServer() async {
        listener?.cancel()
        listener = nil
        logger.debug("OAuth callback server stopped")
    }
    
    /// Opens the authorization URL in the default browser
    public static func openAuthorizationURL(_ url: URL) {
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #else
        // Non-macOS: no system browser API; app should log or display URL via its logger
        var logger = SwiftAgentKitLogging.logger(for: .authentication("OAuthCallbackServer"))
        logger.info("Open this URL in your browser", metadata: ["url": .string(url.absoluteString)])
        #endif
    }
}
