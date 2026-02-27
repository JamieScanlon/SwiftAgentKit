#!/usr/bin/env bash
# Run the Todoist-style OAuth test: start local 401 server, then run MCPManager
# with config so we can see logs and what happens when the client gets oauthDiscoveryRequired.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PORT="${1:-8765}"
cd "$REPO_ROOT"

echo "Building OAuthDiscoveryTest..."
swift build --product OAuthDiscoveryTest 2>&1 | tail -5

echo ""
echo "Starting Todoist-style test server on port $PORT (sends 401 + resource_metadata)..."
python3 "$SCRIPT_DIR/mcp_oauth_test_server.py" "$PORT" &
SERVER_PID=$!
trap "kill $SERVER_PID 2>/dev/null || true" EXIT

# Give server a moment to bind
sleep 1

CONFIG="$SCRIPT_DIR/mcp-config-todoist-style.json"
# Point config at our port
if [[ "$PORT" != "8765" ]]; then
  CONFIG=$(mktemp -t mcp-config.XXXXXX.json)
  sed "s/127.0.0.1:8765/127.0.0.1:$PORT/g" "$SCRIPT_DIR/mcp-config-todoist-style.json" > "$CONFIG"
  trap "kill $SERVER_PID 2>/dev/null || true; rm -f $CONFIG" EXIT
fi

echo "Running OAuthDiscoveryTest with config $CONFIG (same path as production: MCPManager → connectToRemoteServer(serverURL:authProvider:))..."
echo "--- Logs below ---"
SWIFT_LOG_LEVEL=debug "$REPO_ROOT/.build/debug/OAuthDiscoveryTest" "$CONFIG" 2>&1
echo "--- End logs ---"
