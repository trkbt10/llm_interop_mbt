///|
/// Gateway type constructor and enum parsing tests

///|
test "ModelApi and GatewaySurface parse aliases and canonicalize names" {
  assert_eq(ModelApi::from_string("openai"), Some(OpenAICompletions))
  assert_eq(ModelApi::from_string("openai-responses"), Some(OpenAIResponses))
  assert_eq(ModelApi::from_string("claude"), Some(AnthropicMessages))
  assert_eq(ModelApi::from_string("google"), Some(GoogleGenerativeAI))
  assert_eq(ModelApi::from_string("copilot"), Some(GithubCopilot))
  assert_eq(ModelApi::from_string("bedrock"), Some(BedrockConverseStream))
  assert_eq(ModelApi::from_string("ollama"), Some(Ollama))
  assert_eq(ModelApi::from_string("codex"), Some(CodexAppServer))
  assert_eq(ModelApi::from_string("claude-mcp"), Some(ClaudeMcpServe))
  assert_eq(ModelApi::from_string("unknown"), None)

  assert_eq(OpenAICompletions.to_string(), "openai-completions")
  assert_eq(OpenAIResponses.to_string(), "openai-responses")
  assert_eq(AnthropicMessages.to_string(), "anthropic-messages")
  assert_eq(GoogleGenerativeAI.to_string(), "google-generative-ai")
  assert_eq(GithubCopilot.to_string(), "github-copilot")
  assert_eq(BedrockConverseStream.to_string(), "bedrock-converse-stream")
  assert_eq(Ollama.to_string(), "ollama")
  assert_eq(OpenRouter.to_string(), "openrouter")
  assert_eq(CodexAppServer.to_string(), "codex-app-server")
  assert_eq(ClaudeMcpServe.to_string(), "claude-mcp-serve")

  assert_eq(GatewaySurface::from_string("openai"), Some(OpenAI))
  assert_eq(GatewaySurface::from_string("claude"), Some(Anthropic))
  assert_eq(GatewaySurface::from_string("google"), Some(Gemini))
  assert_eq(GatewaySurface::from_string("codex"), Some(Codex))
  assert_eq(GatewaySurface::from_string("unknown"), None)
  assert_eq(GatewaySurface::OpenAI.to_string(), "openai")
  assert_eq(GatewaySurface::Anthropic.to_string(), "anthropic")
  assert_eq(GatewaySurface::Gemini.to_string(), "gemini")
  assert_eq(GatewaySurface::Codex.to_string(), "codex")
}

///|
test "AuthMode and default helper structs initialize expected values" {
  assert_eq(AuthMode::from_string("api_key"), Some(ApiKey))
  assert_eq(AuthMode::from_string("aws"), Some(AwsSdk))
  assert_eq(AuthMode::from_string("oauth"), Some(OAuth))
  assert_eq(AuthMode::from_string("token"), Some(Token))
  assert_eq(AuthMode::from_string("cookie"), None)

  let compat = ModelCompatConfig::default()
  assert_false(compat.supports_store)
  assert_false(compat.supports_reasoning_effort)
  assert_eq(compat.max_tokens_field, "max_tokens")
  assert_eq(compat.thinking_format, "")

  let cost = TokenCost::default()
  assert_eq(cost.input, 0.0)
  assert_eq(cost.output, 0.0)
  assert_eq(cost.cache_read, 0.0)
  assert_eq(cost.cache_write, 0.0)
}

///|
test "Model, provider, and gateway constructors seed stable defaults" {
  let model = ModelConfig::new("gpt-4.1")
  assert_eq(model.id, "gpt-4.1")
  assert_eq(model.name, "gpt-4.1")
  assert_eq(model.api, None)
  assert_eq(model.input, [Text])
  assert_eq(model.context_window, 128000)
  assert_eq(model.max_tokens, 4096)

  let provider = ProviderConfig::new("openai", OpenAIResponses)
  assert_eq(provider.id, "openai")
  assert_eq(provider.auth, ApiKey)
  assert_eq(provider.api, OpenAIResponses)
  assert_true(provider.auth_header)
  assert_true(provider.models_from_endpoint)
  assert_eq(provider.models.length(), 0)
  assert_eq(provider.model_patterns.length(), 0)

  let gateway = GatewayConfig::default()
  assert_eq(gateway.mode, Merge)
  assert_eq(gateway.server.port, 18080)
  assert_eq(gateway.server.host, "0.0.0.0")
}
