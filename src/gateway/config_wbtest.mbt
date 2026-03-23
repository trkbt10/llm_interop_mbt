///|
/// Gateway config parser and serializer tests

///|
fn parse_test_json(json : String) -> Json raise Failure {
  @json.parse(json) catch {
    _ => fail("parse error")
  }
}

///|
fn cleanup_tmp_gateway_config_dir(dir : String) -> Unit {
  @fs.remove_file("\{dir}/valid.json") catch {
    _ => ()
  }
  @fs.remove_file("\{dir}/invalid.json") catch {
    _ => ()
  }
  @fs.remove_dir(dir) catch {
    _ => ()
  }
}

///|
test "parse_config reads providers, models, compat flags, and nested tool configs" {
  let fixture =
    #|{
    #|  "mode": "replace",
    #|  "providers": {
    #|    "openai": {
    #|      "baseURL": "https://api.openai.com/v1",
    #|      "apiKey": "sk-test",
    #|      "auth": "token",
    #|      "api": "openai-responses",
    #|      "headers": { "x-trace": "1", "ignored": 1 },
    #|      "authHeader": false,
    #|      "modelsFromEndpoint": false,
    #|      "modelPatterns": ["gpt-", 7],
    #|      "modelAliases": { "gpt-latest": "gpt-5", "ignored": 1 },
    #|      "codex": {
    #|        "command": "codex serve",
    #|        "approvalPolicy": "on-request",
    #|        "threadSandbox": "workspace-write",
    #|        "turnSandboxPolicy": "workspace-write",
    #|        "turnTimeoutMs": 1234,
    #|        "readTimeoutMs": 5678,
    #|        "stallTimeoutMs": 91011
    #|      },
    #|      "claudeMcp": {
    #|        "command": "claude-bin",
    #|        "args": ["mcp", "serve", 9],
    #|        "env": { "A": "B", "IGNORED": 5 },
    #|        "timeoutMs": 4567
    #|      },
    #|      "models": [
    #|        {
    #|          "id": "gpt-5",
    #|          "name": "GPT-5",
    #|          "api": "openai",
    #|          "reasoning": true,
    #|          "input": ["text", "image", "audio"],
    #|          "cost": {
    #|            "input": 1.2,
    #|            "output": 3.4,
    #|            "cacheRead": 0.5,
    #|            "cacheWrite": 0.6
    #|          },
    #|          "contextWindow": 256000,
    #|          "maxTokens": 8192,
    #|          "headers": { "x-model": "fast", "ignored": 2 },
    #|          "compat": {
    #|            "supportsStore": true,
    #|            "supportsDeveloperRole": true,
    #|            "supportsReasoningEffort": true,
    #|            "supportsUsageInStreaming": true,
    #|            "supportsStrictMode": true,
    #|            "maxTokensField": "max_completion_tokens",
    #|            "thinkingFormat": "openai",
    #|            "requiresToolResultName": true,
    #|            "requiresAssistantAfterToolResult": true,
    #|            "requiresThinkingAsText": true,
    #|            "requiresMistralToolIds": true
    #|          }
    #|        },
    #|        { "id": "gpt-4.1-mini" },
    #|        { "id": "vision-only", "input": ["unknown"] }
    #|      ]
    #|    },
    #|    "fallback": {
    #|      "baseUrl": "https://example.com/api",
    #|      "auth": "cookie",
    #|      "headers": { "x-env": "dev" }
    #|    }
    #|  },
    #|  "server": { "port": 19090, "host": "127.0.0.1" }
    #|}
  let json = parse_test_json(fixture)

  let config = parse_config(json)
  assert_eq(config.mode, Replace)
  assert_eq(config.server.port, 19090)
  assert_eq(config.server.host, "127.0.0.1")
  assert_eq(config.providers.length(), 2)

  match config.providers.get("openai") {
    Some(provider) => {
      assert_eq(provider.base_url, "https://api.openai.com/v1")
      assert_eq(provider.api_key, "sk-test")
      assert_eq(provider.auth, Token)
      assert_eq(provider.api, OpenAIResponses)
      assert_eq(provider.headers.length(), 1)
      assert_eq(provider.headers["x-trace"], "1")
      assert_false(provider.auth_header)
      assert_false(provider.models_from_endpoint)
      assert_eq(provider.model_patterns, ["gpt-"])
      assert_eq(provider.model_aliases.length(), 1)
      assert_eq(provider.model_aliases["gpt-latest"], "gpt-5")

      match provider.codex {
        Some(codex) => {
          assert_eq(codex.command, "codex serve")
          assert_eq(codex.approval_policy, Some("on-request"))
          assert_eq(codex.thread_sandbox, Some("workspace-write"))
          assert_eq(codex.turn_sandbox_policy, Some("workspace-write"))
          assert_eq(codex.turn_timeout_ms, 1234)
          assert_eq(codex.read_timeout_ms, 5678)
          assert_eq(codex.stall_timeout_ms, 91011)
        }
        None => fail("Expected codex config")
      }

      match provider.claude_mcp {
        Some(claude_mcp) => {
          assert_eq(claude_mcp.command, "claude-bin")
          assert_eq(claude_mcp.args, ["mcp", "serve"])
          assert_eq(claude_mcp.env.length(), 1)
          assert_eq(claude_mcp.env["A"], "B")
          assert_eq(claude_mcp.timeout_ms, 4567)
        }
        None => fail("Expected claude MCP config")
      }

      assert_eq(provider.models.length(), 3)

      let model0 = provider.models[0]
      assert_eq(model0.id, "gpt-5")
      assert_eq(model0.name, "GPT-5")
      assert_eq(model0.api, Some(OpenAICompletions))
      assert_true(model0.reasoning)
      assert_eq(model0.input, [Text, Image])
      assert_eq(model0.cost.input, 1.2)
      assert_eq(model0.cost.output, 3.4)
      assert_eq(model0.cost.cache_read, 0.5)
      assert_eq(model0.cost.cache_write, 0.6)
      assert_eq(model0.context_window, 256000)
      assert_eq(model0.max_tokens, 8192)
      assert_eq(model0.headers.length(), 1)
      assert_eq(model0.headers["x-model"], "fast")
      assert_true(model0.compat.supports_store)
      assert_true(model0.compat.supports_developer_role)
      assert_true(model0.compat.supports_reasoning_effort)
      assert_true(model0.compat.supports_usage_in_streaming)
      assert_true(model0.compat.supports_strict_mode)
      assert_eq(model0.compat.max_tokens_field, "max_completion_tokens")
      assert_eq(model0.compat.thinking_format, "openai")
      assert_true(model0.compat.requires_tool_result_name)
      assert_true(model0.compat.requires_assistant_after_tool_result)
      assert_true(model0.compat.requires_thinking_as_text)
      assert_true(model0.compat.requires_mistral_tool_ids)

      let model1 = provider.models[1]
      assert_eq(model1.name, "gpt-4.1-mini")
      assert_eq(model1.api, None)
      assert_false(model1.reasoning)
      assert_eq(model1.input, [Text])
      assert_eq(model1.context_window, 128000)
      assert_eq(model1.max_tokens, 4096)

      let model2 = provider.models[2]
      assert_eq(model2.id, "vision-only")
      assert_eq(model2.input, [Text])
    }
    None => fail("Expected openai provider")
  }

  match config.providers.get("fallback") {
    Some(provider) => {
      assert_eq(provider.base_url, "https://example.com/api")
      assert_eq(provider.auth, ApiKey)
      assert_eq(provider.api, OpenAICompletions)
      assert_eq(provider.headers.length(), 1)
      assert_eq(provider.headers["x-env"], "dev")
      assert_true(provider.auth_header)
      assert_true(provider.models_from_endpoint)
      assert_eq(provider.models.length(), 0)
      assert_eq(provider.model_patterns.length(), 0)
      assert_eq(provider.codex, None)
      assert_eq(provider.claude_mcp, None)
      assert_eq(provider.model_aliases.length(), 0)
    }
    None => fail("Expected fallback provider")
  }
}

///|
test "config helper parsers fall back on empty or mismatched JSON shapes" {
  let config = parse_config({})
  assert_eq(config.mode, Merge)
  assert_eq(config.providers.length(), 0)
  assert_eq(config.server.port, 18080)
  assert_eq(config.server.host, "0.0.0.0")

  assert_eq(parse_mode({ "mode": "merge" }), Merge)
  assert_eq(parse_mode(Json::null()), Merge)
  assert_eq(parse_providers(Json::null()).length(), 0)
  assert_eq(parse_models(Json::null()).length(), 0)
  assert_eq(parse_string_map(Json::null(), "headers").length(), 0)
  assert_eq(parse_string_array(Json::null(), "modelPatterns").length(), 0)
  assert_eq(parse_input_modalities(Json::null()), [Text])
  let cost = parse_cost(Json::null())
  assert_eq(cost.input, 0.0)
  assert_eq(cost.output, 0.0)
  assert_eq(cost.cache_read, 0.0)
  assert_eq(cost.cache_write, 0.0)

  let compat = parse_compat(Json::null())
  assert_false(compat.supports_store)
  assert_false(compat.supports_developer_role)
  assert_false(compat.supports_reasoning_effort)
  assert_false(compat.supports_usage_in_streaming)
  assert_false(compat.supports_strict_mode)
  assert_eq(compat.max_tokens_field, "max_tokens")
  assert_eq(compat.thinking_format, "")
  assert_false(compat.requires_tool_result_name)
  assert_false(compat.requires_assistant_after_tool_result)
  assert_false(compat.requires_thinking_as_text)
  assert_false(compat.requires_mistral_tool_ids)

  let server = parse_server(Json::null())
  assert_eq(server.port, 18080)
  assert_eq(server.host, "0.0.0.0")
  assert_eq(parse_codex_config(Json::null()), None)
  assert_eq(parse_claude_mcp_config(Json::null()), None)
}

///|
test "config object helpers return defaults and filter non-string entries" {
  let obj : Map[String, Json] = {
    "name": "value",
    "maybe": "override",
    "count": 7,
    "ratio": 1.5,
    "flag": true,
    "items": ["a", 1, "b"],
    "map": { "ok": "yes", "bad": 1 },
    "badString": 1,
    "badMaybe": false,
    "badCount": "x",
    "badRatio": "x",
    "badItems": 1,
    "badMap": [],
  }

  assert_eq(obj_string(obj, "name", "fallback"), "value")
  assert_eq(obj_string(obj, "missing", "fallback"), "fallback")
  assert_eq(obj_string(obj, "badString", "fallback"), "fallback")
  assert_eq(obj_opt_string(obj, "maybe", None), Some("override"))
  assert_eq(obj_opt_string(obj, "badMaybe", Some("keep")), Some("keep"))
  assert_eq(obj_int(obj, "count", 9), 7)
  assert_eq(obj_int(obj, "badCount", 9), 9)
  assert_eq(obj_double(obj, "ratio", 2.0), 1.5)
  assert_eq(obj_double(obj, "badRatio", 2.0), 2.0)
  assert_true(obj_bool(obj, "flag"))
  assert_false(obj_bool(obj, "missing"))
  assert_eq(obj_string_array(obj, "items", ["z"]), ["a", "b"])
  assert_eq(obj_string_array(obj, "badItems", ["z"]), ["z"])

  let filtered = obj_string_map(obj, "map", { "fallback": "x" })
  assert_eq(filtered.length(), 1)
  assert_eq(filtered["ok"], "yes")
  assert_eq(obj_string_map(obj, "badMap", { "fallback": "x" })["fallback"], "x")
}

///|
test "config serializers preserve provider and model metadata" {
  let model = {
    ..ModelConfig::new("gpt-4.1"),
    name: "GPT-4.1",
    context_window: 200000,
    max_tokens: 9000,
  }
  match model_to_json(model) {
    {
      "id": String(id),
      "name": String(name),
      "contextWindow": Number(context_window, ..),
      "maxTokens": Number(max_tokens, ..),
      ..
    } => {
      assert_eq(id, "gpt-4.1")
      assert_eq(name, "GPT-4.1")
      assert_eq(context_window.to_int(), 200000)
      assert_eq(max_tokens.to_int(), 9000)
    }
    _ => fail("Expected serialized model config")
  }

  let empty_provider_json = provider_to_json(
    ProviderConfig::new("anthropic", AnthropicMessages),
  )
  assert_false(empty_provider_json.stringify().contains("\"models\""))

  let provider = {
    ..ProviderConfig::new("openai", OpenAIResponses),
    base_url: "https://api.openai.com/v1",
    models: [model],
  }
  match provider_to_json(provider) {
    {
      "baseUrl": String(base_url),
      "api": String(api),
      "models": Array(models),
      ..
    } => {
      assert_eq(base_url, "https://api.openai.com/v1")
      assert_eq(api, "openai-responses")
      assert_eq(models.length(), 1)
    }
    _ => fail("Expected serialized provider config")
  }

  match config_to_json(GatewayConfig::default()) {
    { "server": { "port": Number(port, ..), "host": String(host), .. }, .. } => {
      assert_eq(port.to_int(), 18080)
      assert_eq(host, "0.0.0.0")
    }
    _ => fail("Expected default server config")
  }

  match
    config_to_json({
      mode: Replace,
      providers: { "openai": provider },
      server: { port: 19092, host: "127.0.0.2" },
    }) {
    {
      "providers": { "openai": { "models": Array(models), .. }, .. },
      "server": { "port": Number(port, ..), "host": String(host), .. },
      ..
    } => {
      assert_eq(models.length(), 1)
      assert_eq(port.to_int(), 19092)
      assert_eq(host, "127.0.0.2")
    }
    _ => fail("Expected serialized gateway config")
  }
}

///|
test "load_config_from_file handles success, missing files, and invalid JSON" {
  let dir = "tmp_gateway_config_wbtest"
  cleanup_tmp_gateway_config_dir(dir)
  @fs.create_dir(dir)

  let valid_path = "\{dir}/valid.json"
  @fs.write_string_to_file(
    valid_path, "{\"mode\":\"replace\",\"server\":{\"port\":19091,\"host\":\"127.0.0.3\"}}",
  )
  let valid = load_config_from_file(valid_path)
  assert_eq(valid.mode, Replace)
  assert_eq(valid.server.port, 19091)
  assert_eq(valid.server.host, "127.0.0.3")

  let invalid_path = "\{dir}/invalid.json"
  @fs.write_string_to_file(invalid_path, "{")
  let mut invalid_caught = false
  let _invalid = load_config_from_file(invalid_path) catch {
    GatewayError::ConfigError(message) => {
      assert_eq(message, "Invalid JSON in config")
      invalid_caught = true
      GatewayConfig::default()
    }
    other => {
      ignore(other)
      GatewayConfig::default()
    }
  }
  assert_true(invalid_caught)

  let missing_path = "\{dir}/missing.json"
  let mut missing_caught = false
  let _missing = load_config_from_file(missing_path) catch {
    GatewayError::ConfigError(message) => {
      assert_eq(message, "Failed to read config: " + missing_path)
      missing_caught = true
      GatewayConfig::default()
    }
    other => {
      ignore(other)
      GatewayConfig::default()
    }
  }
  assert_true(missing_caught)

  cleanup_tmp_gateway_config_dir(dir)
}

///|
test "parse_provider and parse_model raise on invalid required fields" {
  let provider_defaults = parse_provider("empty", {})
  assert_eq(provider_defaults.base_url, "")
  assert_eq(provider_defaults.api_key, "")
  assert_eq(provider_defaults.auth, ApiKey)
  assert_eq(provider_defaults.api, OpenAICompletions)

  let mut bad_api_caught = false
  let _bad_provider = parse_provider("broken", { "api": "not-real" }) catch {
    GatewayError::ConfigError(message) => {
      assert_eq(message, "Unknown api: not-real")
      bad_api_caught = true
      ProviderConfig::new("broken", OpenAICompletions)
    }
    other => {
      ignore(other)
      ProviderConfig::new("broken", OpenAICompletions)
    }
  }
  assert_true(bad_api_caught)

  let mut missing_id_caught = false
  let _bad_model = parse_model({ "name": "missing-id" }) catch {
    GatewayError::ConfigError(message) => {
      assert_eq(message, "model.id is required")
      missing_id_caught = true
      ModelConfig::new("fallback")
    }
    other => {
      ignore(other)
      ModelConfig::new("fallback")
    }
  }
  assert_true(missing_id_caught)
}
