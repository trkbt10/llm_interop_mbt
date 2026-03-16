# trkbt10/llm_interop

Use `make check`, `make test`, `make info`, or `make verify` for routine local validation; these targets pin MoonBit to `native js` and avoid falling back to `wasm-gc`.

The native gateway CLI is split into a separate module at `cmd/gateway-native`, so the root module can be checked on `js` without pulling in a native-only main package.

## JS target demo

`cmd/js-test-demo` is a small JS-only demo app that builds a Responses API request and is meant to be exercised with the JavaScript backend.

```bash
moon run --target js cmd/js-test-demo
moon test --target js cmd/js-test-demo
```

If you prefer `make`, the repo also exposes:

```bash
make demo-js
make test-js-demo
```

After `moon build --target js` or `moon test --target js`, generated JavaScript artifacts are written under `_build/js/...`. The test runner executes the emitted Node.js files from there, so this demo gives a concrete package to inspect when you want to verify JS output and test execution end to end.
