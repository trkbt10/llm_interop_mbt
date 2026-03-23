///|
/// Gateway model listing and dialect helper tests

///|
test "parse_models_response skips unsupported shapes and malformed items" {
  assert_eq(parse_models_response("{\"items\":[]}", "test").length(), 0)

  let models = parse_models_response(
    "{\"data\":[{\"id\":\"gpt-4.1\"},{\"name\":\"missing-id\"}]}", "openai",
  )
  assert_eq(models.length(), 1)
  match models[0] {
    { "id": String(id), "owned_by": String(owner), .. } => {
      assert_eq(id, "gpt-4.1")
      assert_eq(owner, "openai")
    }
    _ => fail("Expected filtered model entry")
  }
}

///|
test "Codex model listing helpers enrich configured and fallback models" {
  let model = {
    ..ModelConfig::new("gpt-5"),
    name: "GPT-5",
    input: [Text, Image],
    compat: { ..ModelCompatConfig::default(), supports_reasoning_effort: true },
  }
  match model_config_to_codex_model_json(model, "openai") {
    {
      "displayName": String(name),
      "inputModalities": Array(modalities),
      "defaultReasoningEffort": String(default_effort),
      ..
    } => {
      assert_eq(name, "GPT-5")
      assert_eq(modalities.length(), 2)
      assert_eq(default_effort, "medium")
    }
    _ => fail("Expected Codex model metadata")
  }

  match enrich_remote_model_json("gpt-5", "openai", [model]) {
    { "displayName": String(name), .. } => assert_eq(name, "GPT-5")
    _ => fail("Expected configured model enrichment")
  }

  match enrich_remote_model_json("remote-only", "openai", []) {
    {
      "id": String(id),
      "displayName": String(name),
      "inputModalities": Array(modalities),
      ..
    } => {
      assert_eq(id, "remote-only")
      assert_eq(name, "remote-only")
      assert_eq(modalities.length(), 1)
    }
    _ => fail("Expected fallback remote model shape")
  }
}

///|
test "ClaudeMcpServe dialect spec stays on OpenAI surface with stdio defaults" {
  let spec = ClaudeMcpServe.to_spec()
  assert_eq(spec.id, "claude-mcp-serve")
  assert_eq(ClaudeMcpServe.default_base_url(), "")
  assert_eq(spec.surface, OpenAI)
  assert_eq((spec.completion_path)("/rpc", "ignored", "ignored"), "/rpc")
  assert_eq((spec.models_path)("/rpc", "ignored"), "/rpc")
  assert_eq((spec.auth_headers)("ignored").length(), 0)
}
