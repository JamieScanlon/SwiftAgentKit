#!/usr/bin/env python3
"""
Minimal HTTP server that mimics Todoist MCP: returns 401 with
WWW-Authenticate: Bearer resource_metadata=".../.well-known/oauth-protected-resource/mcp"
so we can observe the client's OAuth discovery flow and logs.
"""
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler

DEFAULT_PORT = 8765


def resource_metadata(port: int) -> str:
    return f"http://127.0.0.1:{port}/.well-known/oauth-protected-resource/mcp"


class TodoistStyleHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        print(f"[server] {args[0]}", file=sys.stderr, flush=True)

    def do_POST(self):
        port = self.server.server_address[1]
        if self.path == "/mcp" or self.path.startswith("/mcp/"):
            self.send_response(401)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header(
                "WWW-Authenticate",
                f'Bearer realm="mcp-server", resource_metadata="{resource_metadata(port)}"',
            )
            self.end_headers()
            body = b'{"jsonrpc":"2.0","id":null,"error":{"code":-32600,"message":"Missing or invalid OAuth authorization"}}'
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    def do_GET(self):
        port = self.server.server_address[1]
        if self.path == "/.well-known/oauth-protected-resource/mcp" or self.path == "/.well-known/oauth-protected-resource":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            # Minimal protected resource metadata so discovery can proceed
            body = b'{"resource":"http://127.0.0.1:' + str(port).encode() + b'/mcp","authorization_servers":[{"issuer":"https://auth.example.com"}]}'
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PORT
    server = HTTPServer(("127.0.0.1", port), TodoistStyleHandler)
    print(f"Todoist-style MCP OAuth test server on http://127.0.0.1:{port}", file=sys.stderr, flush=True)
    print(f"POST /mcp -> 401 WWW-Authenticate resource_metadata={resource_metadata(port)}", file=sys.stderr, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    server.server_close()


if __name__ == "__main__":
    main()
