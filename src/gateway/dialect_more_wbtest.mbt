///|
/// Additional dialect spec and route coverage

///|
test "ModelApi::to_spec covers responses, copilot, bedrock, and codex helpers" {
  let openai = OpenAICompletions.to_spec()
  assert_eq(openai.id, "openai-completions")
  assert_eq(openai.surface, OpenAI)
  assert_eq(
    (openai.completion_path)("/v1", "ignored", "ignored"),
    "/v1/chat/completions",
  )

  let responses = OpenAIResponses.to_spec()
  assert_eq((responses.models_path)("/v1", "ignored"), "/v1/models")

  let anthropic = AnthropicMessages.to_spec()
  assert_eq(anthropic.default_base_url, "https://api.anthropic.com/v1")
  assert_eq(anthropic.surface, Anthropic)
  assert_eq(
    (anthropic.completion_path)("/v1", "ignored", "ignored"),
    "/v1/messages",
  )

  let gemini = GoogleGenerativeAI.to_spec()
  assert_eq(gemini.surface, Gemini)
  assert_eq(
    (gemini.completion_path)("/v1beta", "gemini-2.5-flash", "key"),
    "/v1beta/models/gemini-2.5-flash:generateContent?key=key",
  )

  let copilot = GithubCopilot.to_spec()
  assert_eq(copilot.default_base_url, "https://api.github.com/copilot")
  assert_eq(
    (copilot.completion_path)("/copilot", "ignored", "ignored"),
    "/copilot/chat/completions",
  )
  assert_eq((copilot.models_path)("/copilot", "ignored"), "/copilot/models")

  let bedrock = BedrockConverseStream.to_spec()
  assert_eq(bedrock.default_base_url, "")
  assert_eq(
    (bedrock.completion_path)("/bedrock", "ignored", "ignored"),
    "/bedrock/chat/completions",
  )
  assert_eq((bedrock.models_path)("/bedrock", "ignored"), "/bedrock/models")

  let codex = CodexAppServer.to_spec()
  assert_eq(codex.default_base_url, "")
  assert_eq(codex.surface, Codex)
  assert_eq((codex.completion_path)("/rpc", "ignored", "ignored"), "/rpc")

  let ollama = Ollama.to_spec()
  assert_eq(ollama.default_base_url, "http://localhost:11434")
  assert_eq(
    (ollama.completion_path)("/api", "ignored", "ignored"),
    "/api/chat/completions",
  )
  assert_eq((ollama.models_path)("/api", "ignored"), "/api/models")

  let openrouter = OpenRouter.to_spec()
  assert_eq(openrouter.default_base_url, "https://openrouter.ai/api")
  assert_eq((openrouter.models_path)("/api", "ignored"), "/api/models")

  assert_eq((codex.models_path)("/rpc", "ignored"), "/rpc")
}

///|
test "GatewaySurface::resolve_completion handles none and Codex delegation" {
  match GatewaySurface::Anthropic.resolve_completion("GET", "/bad", "{}") {
    None => ()
    _ => fail("Expected Anthropic miss")
  }

  match GatewaySurface::Gemini.resolve_completion("GET", "/bad", "{}") {
    None => ()
    _ => fail("Expected Gemini miss")
  }

  match
    GatewaySurface::Codex.resolve_completion(
      "POST", "/v1/chat/completions", "{\"model\":\"gpt-4\",\"messages\":[]}",
    ) {
    Some(Completion(dialect~, body~)) => {
      assert_eq(dialect, Codex)
      assert_true(body.contains("\"messages\""))
    }
    _ => fail("Expected Codex completion delegation")
  }

  match GatewaySurface::Codex.resolve_completion("GET", "/bad", "{}") {
    None => ()
    _ => fail("Expected Codex miss")
  }
}
