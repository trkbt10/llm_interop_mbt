#!/usr/bin/env bash
set -euo pipefail

# Codex CLI via MoonBit Gateway + Ollama
# Usage: ./examples/codex/run.sh "your prompt here"
#
# Requires: Ollama running locally (ollama serve)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG="$SCRIPT_DIR/gateway-config.json"
GATEWAY="$REPO_ROOT/cmd/gateway-native/_build/native/debug/build/llm_interop-gateway-native.exe"
MODEL="llama3"
PORT=18080

if ! curl -sf http://localhost:11434/api/tags > /dev/null 2>&1; then
  echo "Error: Ollama is not running. Start it with: ollama serve" >&2
  exit 1
fi

if [ ! -f "$GATEWAY" ]; then
  echo "Gateway binary not found. Building..." >&2
  (cd "$REPO_ROOT/cmd/gateway-native" && moon build --target native)
fi

prompt="${1:-What is 2+2?}"

# Start gateway in background
"$GATEWAY" -c "$CONFIG" &
GW_PID=$!
trap 'kill $GW_PID 2>/dev/null || true' EXIT

# Wait for gateway to be ready
for i in $(seq 1 20); do
  if curl -sf "http://localhost:$PORT/v1/models" > /dev/null 2>&1; then
    break
  fi
  sleep 0.25
done

# Run Codex CLI
codex -m "$MODEL" \
  -c 'model_providers.gw.name="Gateway"' \
  -c "model_providers.gw.base_url=\"http://localhost:$PORT/v1\"" \
  -c 'model_provider="gw"' \
  exec "$prompt"
