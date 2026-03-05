# Load .env if exists
ifneq (,$(wildcard .env))
  include .env
  export
endif

# Provider for integration tests (anthropic, openai, groq)
PROVIDER ?=

.PHONY: test test-native test-js test-client test-integration

# Unit tests
test:
	moon test --target native
	moon test --target js

test-native:
	moon test --target native

test-js:
	moon test --target js

test-client:
	moon test --target native src/client
	moon test --target js src/client

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
