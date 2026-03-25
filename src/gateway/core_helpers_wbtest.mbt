///|
/// Gateway core helper tests

///|
test "prepare_upstream applies model alias replacement" {
  let provider = {
    ..ProviderConfig::new("openai", OpenAICompletions),
    model_aliases: { "o1": "backend-o1" },
  }
  let req = prepare_upstream(
    provider,
    "{\"model\":\"o1\",\"messages\":[]}",
    OpenAI,
    "o1",
    "https://api.openai.com/v1",
    "sk-test",
  )
  let parsed : Json = @json.parse(req.body) catch { _ => fail("parse error") }
  match parsed {
    { "model": String(model), .. } => assert_eq(model, "backend-o1")
    _ => fail("Expected aliased model field")
  }
}

///|
test "transform_for_provider uses model-specific transform context" {
  let provider = {
    ..ProviderConfig::new("openai", OpenAICompletions),
    models: [
      {
        ..ModelConfig::new("o1-mini"),
        max_tokens: 4096,
        compat: {
          ..ModelCompatConfig::default(),
          max_tokens_field: "max_completion_tokens",
        },
      },
    ],
  }
  let body = "{\"model\":\"o1-mini\",\"messages\":[],\"max_tokens\":9}"
  let result = transform_for_provider(provider, body, OpenAI, OpenAI, "o1-mini")
  let parsed : Json = @json.parse(result) catch { _ => fail("parse error") }
  match parsed {
    { "max_completion_tokens": Number(value, ..), .. } =>
      assert_eq(value.to_int(), 9)
    _ => fail("Expected model-specific max token field")
  }
}

///|
test "panic prepare_upstream rejects model alias replacement for non-object bodies" {
  let provider = {
    ..ProviderConfig::new("openai", OpenAICompletions),
    model_aliases: { "o1": "backend-o1" },
  }
  ignore(
    prepare_upstream(
      provider,
      "[]",
      OpenAI,
      "o1",
      "https://api.openai.com/v1",
      "sk-test",
    ),
  )
}

///|
test "panic prepare_upstream rejects model alias replacement for invalid JSON bodies" {
  let provider = {
    ..ProviderConfig::new("openai", OpenAICompletions),
    model_aliases: { "o1": "backend-o1" },
  }
  ignore(
    prepare_upstream(
      provider,
      "{",
      OpenAI,
      "o1",
      "https://api.openai.com/v1",
      "sk-test",
    ),
  )
}

///|
test "panic transform_for_provider rejects same-surface non-object bodies when normalization is required" {
  let provider = {
    ..ProviderConfig::new("openai", OpenAICompletions),
    models: [
      {
        ..ModelConfig::new("o1-mini"),
        max_tokens: 4096,
        compat: {
          ..ModelCompatConfig::default(),
          max_tokens_field: "max_completion_tokens",
        },
      },
    ],
  }
  ignore(transform_for_provider(provider, "[]", OpenAI, OpenAI, "o1-mini"))
}

///|
test "panic transform_for_provider rejects same-surface invalid JSON when normalization is required" {
  let provider = {
    ..ProviderConfig::new("openai", OpenAICompletions),
    models: [
      {
        ..ModelConfig::new("o1-mini"),
        max_tokens: 4096,
        compat: {
          ..ModelCompatConfig::default(),
          max_tokens_field: "max_completion_tokens",
        },
      },
    ],
  }
  ignore(transform_for_provider(provider, "{", OpenAI, OpenAI, "o1-mini"))
}
