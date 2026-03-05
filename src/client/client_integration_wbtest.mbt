///|
/// Integration tests - requires API keys in environment variables

// =============================================================================
// Anthropic Tests
// =============================================================================

///|
async test "integration_anthropic_chat" {
  let api_key = match @sys.get_env_var("ANTHROPIC_API_KEY") {
    Some(k) => k
    None => {
      println("[SKIP] integration_anthropic_chat: ANTHROPIC_API_KEY not set")
      return
    }
  }
  println("[RUN] integration_anthropic_chat")
  let config = ClientConfig::new(
    Provider::Anthropic,
    api_key,
    "claude-sonnet-4-20250514",
    max_tokens=100,
  )
  let messages : Array[@types.ModelMessage] = [
    @types.ModelMessage::User(content="Say 'hello' only.", name=None),
  ]
  let response = chat(config, messages)
  match response {
    @types.ModelResponse::Text(text) => {
      println("[OK] got: " + text)
      assert_true(text.to_lower().contains("hello"))
    }
    @types.ModelResponse::ModelError(err) => fail("API error: " + err)
    _ => fail("Unexpected response")
  }
}

///|
async test "integration_anthropic_stream" {
  let api_key = match @sys.get_env_var("ANTHROPIC_API_KEY") {
    Some(k) => k
    None => {
      println("[SKIP] integration_anthropic_stream: ANTHROPIC_API_KEY not set")
      return
    }
  }
  println("[RUN] integration_anthropic_stream")
  let config = ClientConfig::new(
    Provider::Anthropic,
    api_key,
    "claude-sonnet-4-20250514",
    max_tokens=100,
  )
  let messages : Array[@types.ModelMessage] = [
    @types.ModelMessage::User(content="Count 1 to 3.", name=None),
  ]
  let mut events = 0
  let response = chat_stream(config, messages, on_event=fn(_) {
    events = events + 1
  })
  println("[OK] received \{events} events")
  assert_true(events > 0)
  match response {
    @types.ModelResponse::Text(text) => {
      assert_true(text.contains("1"))
      assert_true(text.contains("3"))
    }
    _ => fail("Unexpected response")
  }
}

///|
async test "integration_anthropic_tool" {
  let api_key = match @sys.get_env_var("ANTHROPIC_API_KEY") {
    Some(k) => k
    None => {
      println("[SKIP] integration_anthropic_tool: ANTHROPIC_API_KEY not set")
      return
    }
  }
  println("[RUN] integration_anthropic_tool")
  let config = ClientConfig::new(
    Provider::Anthropic,
    api_key,
    "claude-sonnet-4-20250514",
    max_tokens=200,
  )
  let messages : Array[@types.ModelMessage] = [
    @types.ModelMessage::User(
      content="Get weather in Tokyo using the tool.",
      name=None,
    ),
  ]
  let tools : Array[@types.ToolDefinition] = [
    @types.ToolDefinition::new(
      name="get_weather",
      description="Get weather for a location",
      parameters={
        "type": "object",
        "properties": { "location": { "type": "string" } },
        "required": ["location"],
      },
    ),
  ]
  let response = chat(config, messages, tools~)
  match response {
    @types.ModelResponse::ToolCalls(calls) => {
      println("[OK] tool called: " + calls[0].name)
      assert_true(calls.length() > 0)
      assert_eq(calls[0].name, "get_weather")
    }
    _ => fail("Expected tool call")
  }
}

// =============================================================================
// OpenAI Tests
// =============================================================================

///|
async test "integration_openai_chat" {
  let api_key = match @sys.get_env_var("OPENAI_API_KEY") {
    Some(k) => k
    None => {
      println("[SKIP] integration_openai_chat: OPENAI_API_KEY not set")
      return
    }
  }
  println("[RUN] integration_openai_chat")
  let config = ClientConfig::new(
    Provider::OpenAI,
    api_key,
    "gpt-4o-mini",
    max_tokens=100,
  )
  let messages : Array[@types.ModelMessage] = [
    @types.ModelMessage::User(content="Say 'hello' only.", name=None),
  ]
  let response = chat(config, messages)
  match response {
    @types.ModelResponse::Text(text) => {
      println("[OK] got: " + text)
      assert_true(text.to_lower().contains("hello"))
    }
    @types.ModelResponse::ModelError(err) => fail("API error: " + err)
    _ => fail("Unexpected response")
  }
}

///|
async test "integration_openai_stream" {
  let api_key = match @sys.get_env_var("OPENAI_API_KEY") {
    Some(k) => k
    None => {
      println("[SKIP] integration_openai_stream: OPENAI_API_KEY not set")
      return
    }
  }
  println("[RUN] integration_openai_stream")
  let config = ClientConfig::new(
    Provider::OpenAI,
    api_key,
    "gpt-4o-mini",
    max_tokens=100,
  )
  let messages : Array[@types.ModelMessage] = [
    @types.ModelMessage::User(content="Count 1 to 3.", name=None),
  ]
  let mut events = 0
  let response = chat_stream(config, messages, on_event=fn(_) {
    events = events + 1
  })
  println("[OK] received \{events} events")
  assert_true(events > 0)
  match response {
    @types.ModelResponse::Text(text) => {
      assert_true(text.contains("1"))
      assert_true(text.contains("3"))
    }
    _ => fail("Unexpected response")
  }
}

///|
async test "integration_openai_tool" {
  let api_key = match @sys.get_env_var("OPENAI_API_KEY") {
    Some(k) => k
    None => {
      println("[SKIP] integration_openai_tool: OPENAI_API_KEY not set")
      return
    }
  }
  println("[RUN] integration_openai_tool")
  let config = ClientConfig::new(
    Provider::OpenAI,
    api_key,
    "gpt-4o-mini",
    max_tokens=200,
  )
  let messages : Array[@types.ModelMessage] = [
    @types.ModelMessage::User(
      content="Get weather in Tokyo using the tool.",
      name=None,
    ),
  ]
  let tools : Array[@types.ToolDefinition] = [
    @types.ToolDefinition::new(
      name="get_weather",
      description="Get weather for a location",
      parameters={
        "type": "object",
        "properties": { "location": { "type": "string" } },
        "required": ["location"],
      },
    ),
  ]
  let response = chat(config, messages, tools~)
  match response {
    @types.ModelResponse::ToolCalls(calls) => {
      println("[OK] tool called: " + calls[0].name)
      assert_true(calls.length() > 0)
      assert_eq(calls[0].name, "get_weather")
    }
    _ => fail("Expected tool call")
  }
}

// =============================================================================
// Groq Tests (OpenAI Compatible)
// =============================================================================

///|
async test "integration_groq_chat" {
  let api_key = match @sys.get_env_var("GROQ_API_KEY") {
    Some(k) => k
    None => {
      println("[SKIP] integration_groq_chat: GROQ_API_KEY not set")
      return
    }
  }
  println("[RUN] integration_groq_chat")
  let config = ClientConfig::new(
    Provider::OpenAICompatible(base_url="https://api.groq.com/openai"),
    api_key,
    "llama-3.1-8b-instant",
    max_tokens=100,
  )
  let messages : Array[@types.ModelMessage] = [
    @types.ModelMessage::User(content="Say 'hello' only.", name=None),
  ]
  let response = chat(config, messages)
  match response {
    @types.ModelResponse::Text(text) => {
      println("[OK] got: " + text)
      assert_true(text.to_lower().contains("hello"))
    }
    @types.ModelResponse::ModelError(err) => fail("API error: " + err)
    _ => fail("Unexpected response")
  }
}

///|
async test "integration_groq_stream" {
  let api_key = match @sys.get_env_var("GROQ_API_KEY") {
    Some(k) => k
    None => {
      println("[SKIP] integration_groq_stream: GROQ_API_KEY not set")
      return
    }
  }
  println("[RUN] integration_groq_stream")
  let config = ClientConfig::new(
    Provider::OpenAICompatible(base_url="https://api.groq.com/openai"),
    api_key,
    "llama-3.1-8b-instant",
    max_tokens=100,
  )
  let messages : Array[@types.ModelMessage] = [
    @types.ModelMessage::User(content="Count 1 to 3.", name=None),
  ]
  let mut events = 0
  let response = chat_stream(config, messages, on_event=fn(_) {
    events = events + 1
  })
  println("[OK] received \{events} events")
  assert_true(events > 0)
  match response {
    @types.ModelResponse::Text(text) => {
      assert_true(text.contains("1"))
      assert_true(text.contains("3"))
    }
    _ => fail("Unexpected response")
  }
}
