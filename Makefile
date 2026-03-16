# Load .env if exists
ifneq (,$(wildcard .env))
  include .env
  export
endif

# Provider for integration tests (anthropic, openai, groq)
PROVIDER ?=
MOON_TARGETS ?= native js

.PHONY: check check-native check-js test test-native test-js test-client info info-native info-js verify test-integration demo-js test-js-demo ui-dev ui-build gateway

# Default local verification targets. We intentionally avoid bare `moon check`
# so MoonBit does not fall back to wasm-gc during routine development.
# The native gateway CLI now lives in `cmd/gateway-native` as a separate module.
check:
	for target in $(MOON_TARGETS); do \
		moon check --target $$target; \
	done

check-native:
	moon check --target native

check-js:
	moon check --target js

# Unit tests
test:
	moon test --target native
	moon test --target js

test-native:
	moon test --target native

test-js:
	moon test --target js

demo-js:
	moon run --target js cmd/js-test-demo

test-js-demo:
	moon test --target js cmd/js-test-demo

test-client:
	moon test --target native src/client
	moon test --target js src/client

info:
	for target in $(MOON_TARGETS); do \
		moon info --target $$target; \
	done

info-native:
	moon info --target native

info-js:
	moon info --target js

verify: check test info

# Integration tests
# Usage:
#   make test-integration PROVIDER=anthropic
#   make test-integration PROVIDER=openai
#   make test-integration PROVIDER=groq
test-integration:
ifeq ($(PROVIDER),)
	$(error Usage: make test-integration PROVIDER=anthropic|openai|groq)
endif
ifeq ($(PROVIDER),anthropic)
  ifndef ANTHROPIC_API_KEY
	$(error ANTHROPIC_API_KEY not set)
  endif
endif
ifeq ($(PROVIDER),openai)
  ifndef OPENAI_API_KEY
	$(error OPENAI_API_KEY not set)
  endif
endif
ifeq ($(PROVIDER),groq)
  ifndef GROQ_API_KEY
	$(error GROQ_API_KEY not set)
  endif
endif
	moon test --target native src/client --filter 'integration_$(PROVIDER)*'
	moon test --target js src/client --filter 'integration_$(PROVIDER)*'

# Gateway
gateway:
	cd cmd/gateway-native && moon run . --target native -- --config ../../gateway-config.json

# UI development
ui-dev:
	cd ui && npm run dev

ui-build:
	cd ui && npm run build
