#!/usr/bin/env bash
set -euo pipefail

# Claude Code via MoonBit Gateway + Codex App Server
#
# Starts the gateway with Anthropic dialect, backed by `codex app-server`,
# then launches Claude Code pointing at the gateway.
#
# Usage:
#   ./examples/claude-via-codex/run.sh                # interactive claude
#   ./examples/claude-via-codex/run.sh --print "Hi"   # one-shot

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG="$SCRIPT_DIR/gateway-config.json"
PORT=18080

# Build gateway if needed
GATEWAY="$REPO_ROOT/cmd/gateway-native/_build/native/debug/build/llm_interop-gateway-native.exe"
if [ ! -f "$GATEWAY" ]; then
  echo "Gateway binary not found. Building..." >&2
  (cd "$REPO_ROOT/cmd/gateway-native" && moon build --target native)
fi

# Start gateway in background
echo "Starting gateway (dialect=anthropic, backend=codex app-server)..." >&2
"$GATEWAY" --dialect anthropic --config "$CONFIG" --port "$PORT" &
GW_PID=$!
trap 'kill $GW_PID 2>/dev/null || true; wait $GW_PID 2>/dev/null || true' EXIT

# Wait for gateway to be ready
for i in $(seq 1 30); do
  if curl -sf "http://localhost:$PORT/health" > /dev/null 2>&1; then
    echo "Gateway ready on port $PORT" >&2
    break
  fi
  if ! kill -0 "$GW_PID" 2>/dev/null; then
    echo "Error: Gateway process exited unexpectedly" >&2
    exit 1
  fi
  sleep 0.25
done

# Launch Claude Code
exec env \
  ANTHROPIC_BASE_URL="http://localhost:$PORT" \
  ANTHROPIC_AUTH_TOKEN=dummy \
  claude "$@"
