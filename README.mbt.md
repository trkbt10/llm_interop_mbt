# trkbt10/llm_interop

Use `make check`, `make test`, `make info`, or `make verify` for routine local validation; these targets pin MoonBit to `native js` and avoid falling back to `wasm-gc`.

The native gateway CLI is split into a separate module at `cmd/gateway-native`, so the root module can be checked on `js` without pulling in a native-only main package.
