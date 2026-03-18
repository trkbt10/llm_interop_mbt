## Development

### Build and Test

```bash
make check          # Type-check for native and js targets
make test           # Run unit tests for native and js targets
make info           # Generate .mbti interface files
make verify         # Run check + test + info (full local verification)
```

### Individual Target Commands

```bash
make check-native   # Type-check native only
make check-js       # Type-check js only
make test-native    # Test native only
make test-js        # Test js only
```

### Integration Tests

```bash
make test-integration PROVIDER=anthropic   # Requires ANTHROPIC_API_KEY
make test-integration PROVIDER=openai      # Requires OPENAI_API_KEY
make test-integration PROVIDER=groq        # Requires GROQ_API_KEY
```

### Native Gateway

The native gateway CLI is a **separate MoonBit module** at `cmd/gateway-native/`. It is excluded from the default `moon check` / `moon test` targets.

```bash
make gateway        # Run the native gateway with gateway-config.json
```

### JS Target Demo

```bash
make demo-js        # moon run --target js cmd/js-test-demo
make test-js-demo   # moon test --target js cmd/js-test-demo
```
