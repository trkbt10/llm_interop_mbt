///|
/// Responses pipeline helper tests

///|
test "prepare_responses_api_upstream applies model aliases, auth, headers, and stream" {
  let provider = {
    ..ProviderConfig::new("openai", OpenAIResponses),
    headers: { "X-Test": "1" },
    model_aliases: { "gpt-4.1": "backend-gpt" },
  }
  let upstream = prepare_responses_api_upstream(
    provider,
    { "model": "gpt-4.1", "input": "Hello" },
    "gpt-4.1",
    "https://api.example.com/v1",
    "sk-test",
    stream=true,
  )
  assert_eq(upstream.origin, "https://api.example.com")
  assert_eq(upstream.path, "/v1/responses")
  assert_eq(upstream.headers.get("Authorization"), Some("Bearer sk-test"))
  assert_eq(upstream.headers.get("X-Test"), Some("1"))

  let body : Json = @json.parse(upstream.body) catch {
    _ => fail("parse error")
  }
  match body {
    { "model": String(model), "stream": True, .. } =>
      assert_eq(model, "backend-gpt")
    _ => fail("Expected aliased stream body")
  }
}

///|
test "prepare_responses_api_upstream preserves native body when aliasing is not needed" {
  let provider = ProviderConfig::new("openai", OpenAIResponses)
  let upstream = prepare_responses_api_upstream(
    provider,
    { "model": "gpt-4.1", "input": "Hello" },
    "gpt-4.1",
    "https://api.example.com/v1",
    "sk-test",
  )
  let body : Json = @json.parse(upstream.body) catch {
    _ => fail("parse error")
  }
  match body {
    { "model": String(model), .. } => {
      assert_eq(model, "gpt-4.1")
      assert_false(upstream.body.contains("\"stream\":true"))
    }
    _ => fail("Expected original model in body")
  }
}

///|
test "response ID helpers delegate to interop SoT" {
  assert_eq(
    extract_response_id("{\"id\":\"chatcmpl-123\"}", "gpt-4"),
    "chatcmpl-123",
  )
  assert_eq(
    extract_response_id("{\"status\":\"ok\"}", "gpt-4.1"),
    "resp_gpt-4.1",
  )
  assert_eq(fallback_response_id("gpt-4.1"), "resp_gpt-4.1")
}

///|
test "create_responses_api_translator selects correct variants" {
  match
    create_responses_api_translator(
      OpenAIResponses,
      response_id="resp_1",
      model="gpt-4.1",
    ) {
    PassThrough => ()
    _ => fail("Expected pass-through translator")
  }

  match
    create_responses_api_translator(
      OpenAICompletions,
      response_id="resp_1",
      model="gpt-4.1",
    ) {
    Harmony(_) => ()
    _ => fail("Expected harmony translator")
  }

  match
    create_responses_api_translator(
      AnthropicMessages,
      response_id="resp_1",
      model="claude-sonnet",
    ) {
    Anthropic(_) => ()
    _ => fail("Expected anthropic translator")
  }

  match
    create_responses_api_translator(
      GoogleGenerativeAI,
      response_id="resp_1",
      model="gemini-2.5-flash",
    ) {
    Gemini(_) => ()
    _ => fail("Expected gemini translator")
  }

  match
    create_responses_api_translator(
      CodexAppServer,
      response_id="resp_1",
      model="codex",
    ) {
    Codex(_) => ()
    _ => fail("Expected codex translator")
  }
}

///|
test "prepare_responses_api_upstream converts harmony, anthropic, and gemini request bodies" {
  let request : Json = {
    "model": "demo",
    "input": [{ "role": "user", "content": "Hello" }],
  }

  let harmony_provider = ProviderConfig::new("openai", OpenAICompletions)
  let harmony_upstream = prepare_responses_api_upstream(
    harmony_provider, request, "demo", "https://api.example.com/v1", "sk-test",
  )
  let harmony_json : Json = @json.parse(harmony_upstream.body) catch {
    _ => fail("parse error")
  }
  match harmony_json {
    { "messages": Array(messages), "stream": False, .. } =>
      assert_eq(messages.length(), 1)
    _ => fail("Expected chat-completions request body")
  }

  let anthropic_provider = ProviderConfig::new("anthropic", AnthropicMessages)
  let anthropic_upstream = prepare_responses_api_upstream(
    anthropic_provider, request, "demo", "https://api.anthropic.com/v1", "sk-test",
  )
  let anthropic_json : Json = @json.parse(anthropic_upstream.body) catch {
    _ => fail("parse error")
  }
  match anthropic_json {
    { "messages": Array(messages), .. } => assert_eq(messages.length(), 1)
    _ => fail("Expected anthropic request body")
  }

  let anthropic_stream = prepare_responses_api_upstream(
    anthropic_provider,
    request,
    "demo",
    "https://api.anthropic.com/v1",
    "sk-test",
    stream=true,
  )
  let anthropic_stream_json : Json = @json.parse(anthropic_stream.body) catch {
    _ => fail("parse error")
  }
  match anthropic_stream_json {
    { "messages": Array(messages), "stream": True, .. } =>
      assert_eq(messages.length(), 1)
    _ => fail("Expected anthropic streaming request body")
  }

  let gemini_provider = ProviderConfig::new("gemini", GoogleGenerativeAI)
  let gemini_upstream = prepare_responses_api_upstream(
    gemini_provider, request, "demo", "https://generativelanguage.googleapis.com/v1beta",
    "ignored",
  )
  let gemini_json : Json = @json.parse(gemini_upstream.body) catch {
    _ => fail("parse error")
  }
  match gemini_json {
    { "contents": Array(contents), .. } => assert_eq(contents.length(), 1)
    _ => fail("Expected gemini request body")
  }
}

///|
test "prepare_responses_api_upstream preserves structured output across streaming request conversions" {
  let request : Json = {
    "model": "demo",
    "input": [{ "role": "user", "content": "Return JSON" }],
    "text": {
      "format": {
        "type": "json_schema",
        "name": "answer",
        "description": "Structured answer",
        "schema": {
          "type": "object",
          "properties": { "url": { "type": "string", "format": "uri" } },
        },
        "strict": true,
      },
    },
  }

  let harmony_provider = ProviderConfig::new("openai", OpenAICompletions)
  let harmony_upstream = prepare_responses_api_upstream(
    harmony_provider,
    request,
    "demo",
    "https://api.example.com/v1",
    "sk-test",
    stream=true,
  )
  let harmony_json : Json = @json.parse(harmony_upstream.body) catch {
    _ => fail("parse error")
  }
  match harmony_json {
    {
      "stream": True,
      "response_format": {
        "type": "json_schema",
        "json_schema": {
          "name": "answer",
          "description": "Structured answer",
          "schema": {
            "properties": { "url": { "type": String("string"), .. }, .. },
            "required": ["url"],
            "additionalProperties": False,
            ..
          },
          "strict": True,
          ..
        },
        ..
      },
      ..
    } => ()
    _ => fail("Expected streaming chat request with normalized response_format")
  }

  let anthropic_provider = ProviderConfig::new("anthropic", AnthropicMessages)
  let anthropic_upstream = prepare_responses_api_upstream(
    anthropic_provider,
    request,
    "demo",
    "https://api.anthropic.com/v1",
    "sk-test",
    stream=true,
  )
  let anthropic_json : Json = @json.parse(anthropic_upstream.body) catch {
    _ => fail("parse error")
  }
  match anthropic_json {
    {
      "stream": True,
      "output_config": {
        "format": {
          "type": "json_schema",
          "schema": {
            "properties": {
              "url": { "type": String("string"), "format": String("uri"), .. },
              ..
            },
            ..
          },
          ..
        },
        ..
      },
      ..
    } => ()
    _ => fail("Expected Anthropic streaming request with preserved schema body")
  }

  let gemini_provider = ProviderConfig::new("gemini", GoogleGenerativeAI)
  let gemini_upstream = prepare_responses_api_upstream(
    gemini_provider,
    request,
    "demo",
    "https://generativelanguage.googleapis.com/v1beta",
    "ignored",
    stream=true,
  )
  let gemini_json : Json = @json.parse(gemini_upstream.body) catch {
    _ => fail("parse error")
  }
  match gemini_json {
    {
      "generationConfig": {
        "responseMimeType": "application/json",
        "responseJsonSchema": {
          "properties": {
            "url": { "type": String("string"), "format": String("uri"), .. },
            ..
          },
          ..
        },
        ..
      },
      ..
    } => ()
    _ => fail("Expected Gemini streaming request with structured output config")
  }
  assert_true(
    gemini_upstream.path.contains(":streamGenerateContent?alt=sse&key="),
  )
}

///|
test "prepare_responses_api_upstream: same Responses contract can target OpenAI, Anthropic, and Gemini backends" {
  let request : Json = {
    "model": "demo",
    "input": [{ "role": "user", "content": "Return a URL" }],
    "tools": [
      {
        "type": "function",
        "name": "lookup_verification_url",
        "description": "Return URL",
        "parameters": {
          "type": "object",
          "properties": { "label": { "type": "string" } },
          "required": ["label"],
        },
      },
    ],
    "text": {
      "format": {
        "type": "json_schema",
        "name": "answer",
        "schema": {
          "type": "object",
          "properties": { "url": { "type": "string" } },
          "required": ["url"],
        },
      },
    },
  }

  let openai_upstream = prepare_responses_api_upstream(
    ProviderConfig::new("openai", OpenAIResponses),
    request,
    "demo",
    "https://api.example.com/v1",
    "sk-test",
  )
  let openai_json : Json = @json.parse(openai_upstream.body) catch {
    _ => fail("parse error")
  }
  match openai_json {
    {
      "input": Array(_),
      "tools": Array(tools),
      "text": { "format": { "type": String("json_schema"), .. }, .. },
      ..
    } => assert_eq(tools.length(), 1)
    _ => fail("Expected Responses-native body")
  }

  let anthropic_upstream = prepare_responses_api_upstream(
    ProviderConfig::new("anthropic", AnthropicMessages),
    request,
    "demo",
    "https://api.anthropic.com/v1",
    "sk-test",
  )
  let anthropic_json : Json = @json.parse(anthropic_upstream.body) catch {
    _ => fail("parse error")
  }
  match anthropic_json {
    {
      "messages": Array(messages),
      "tools": Array(tools),
      "output_config": { "format": { "type": String("json_schema"), .. }, .. },
      ..
    } => {
      assert_eq(messages.length(), 1)
      assert_eq(tools.length(), 1)
    }
    _ => fail("Expected Anthropic body from Responses request")
  }

  let gemini_upstream = prepare_responses_api_upstream(
    ProviderConfig::new("gemini", GoogleGenerativeAI),
    request,
    "demo",
    "https://generativelanguage.googleapis.com/v1beta",
    "ignored",
  )
  let gemini_json : Json = @json.parse(gemini_upstream.body) catch {
    _ => fail("parse error")
  }
  match gemini_json {
    {
      "contents": Array(contents),
      "tools": Array([{ "functionDeclarations": Array(decls), .. }]),
      "generationConfig": {
        "responseMimeType": String("application/json"),
        "responseJsonSchema": { "type": String("object"), .. },
        ..
      },
      ..
    } => {
      assert_eq(contents.length(), 1)
      assert_eq(decls.length(), 1)
    }
    _ => fail("Expected Gemini body from Responses request")
  }
}

///|
test "ResponsesApiTranslator::translate passthrough preserves native events" {
  let event : @sse.SseEvent = {
    event: "response.completed",
    data: { "type": "response.completed" },
  }
  let translated = PassThrough.translate(event)
  assert_eq(translated.length(), 1)
  assert_eq(translated[0].0, "response.completed")
  match translated[0].1 {
    { "type": String(type_), .. } => assert_eq(type_, "response.completed")
    _ => fail("Expected passthrough event payload")
  }
}

///|
test "ResponsesApiTranslator::translate covers anthropic and gemini translators" {
  let anthropic = create_responses_api_translator(
    AnthropicMessages,
    response_id="resp_a",
    model="claude",
  )
  let anthropic_events = anthropic.translate({
    event: "message_start",
    data: { "type": "message_start", "message": { "id": "msg_1" } },
  })
  assert_true(anthropic_events.length() > 0)

  let gemini = create_responses_api_translator(
    GoogleGenerativeAI,
    response_id="resp_g",
    model="gemini-2.5-flash",
  )
  let gemini_events = gemini.translate({
    event: "",
    data: { "candidates": [{ "content": { "parts": [{ "text": "Hi" }] } }] },
  })
  assert_true(gemini_events.length() > 0)

  let codex = create_responses_api_translator(
    CodexAppServer,
    response_id="resp_c",
    model="codex",
  )
  let codex_events = codex.translate({
    event: "message",
    data: { "method": "item/agentMessage/delta", "params": { "delta": "Hi" } },
  })
  assert_true(codex_events.length() > 0)
}

///|
test "to_synthetic_sse_events returns expected events for supported backends" {
  let responses_body = @openai_responses_contract.model_response_to_responses_json(
    @types.ModelResponse::Text("Hello"),
    response_id="resp_1",
    model="gpt-4.1",
  )
  let responses_events = to_synthetic_sse_events(
    OpenAIResponses,
    responses_body.stringify(),
  )
  assert_eq(responses_events.map(fn(event) { event.event }), [
    "response.created", "response.in_progress", "response.output_item.added", "response.output_text.delta",
    "response.output_text.done", "response.output_item.done", "response.completed",
  ])
  assert_eq(to_synthetic_sse_events(OpenAICompletions, "not json").length(), 0)

  let chat_response =
    #|{"id":"chatcmpl-1","object":"chat.completion","model":"gpt-4","choices":[{"index":0,"message":{"role":"assistant","content":"Hello!"},"finish_reason":"stop"}]}
  let events = to_synthetic_sse_events(OpenAICompletions, chat_response)
  assert_eq(events.length(), 3)
  assert_eq(events[0].event, "")
  assert_eq(events[2].event, "")

  assert_true(
    to_synthetic_sse_events(
      AnthropicMessages,
      "{\"content\":[{\"type\":\"text\",\"text\":\"Hi\"}],\"stop_reason\":\"end_turn\",\"model\":\"claude\"}",
    ).length() >
    0,
  )
  assert_eq(
    to_synthetic_sse_events(
      GoogleGenerativeAI,
      "{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Hi\"}]}}]}",
    ).length(),
    1,
  )
  assert_eq(
    to_synthetic_sse_events(
      CodexAppServer,
      "[{\"method\":\"item/agentMessage/delta\",\"params\":{\"delta\":\"Hi\"}}]",
    ).length(),
    1,
  )
}

///|
test "parse_responses_api_result handles native responses and translated chat completions" {
  let native_model = "gpt-4.1"
  let native = parse_responses_api_result(
    OpenAIResponses,
    "{\"id\":\"resp_1\",\"output\":[{\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":\"Hi there!\"}]}]}",
    model=native_model,
  )
  match native {
    @types.ModelResponse::Text(text) => assert_eq(text, "Hi there!")
    _ => fail("Expected native text response")
  }

  let chat_body =
    #|{"id":"chatcmpl-1","object":"chat.completion","model":"gpt-4","choices":[{"index":0,"message":{"role":"assistant","content":"Hello!"},"finish_reason":"stop"}]}
  let translated_model = "gpt-4"
  let translated = parse_responses_api_result(
    OpenAICompletions,
    chat_body,
    model=translated_model,
  )
  match translated {
    @types.ModelResponse::Text(text) => assert_eq(text, "Hello!")
    _ => fail("Expected translated text response")
  }
}

///|
test "parse_responses_api_result preserves Anthropic citations through Responses pipeline" {
  let anthropic_body =
    #|{"id":"msg_cited","model":"claude-sonnet-4-20250514","content":[{"type":"text","text":"Weather details","citations":[{"type":"web_search_result_location","cited_text":"Weather details","encrypted_index":"enc_tokyo","title":"Tokyo Weather","url":"https://example.com/tokyo"}]}],"stop_reason":"end_turn"}
  match
    parse_responses_api_result(
      AnthropicMessages,
      anthropic_body,
      model="claude-sonnet-4-20250514",
    ) {
    @types.ModelResponse::RichText(rich) => {
      assert_eq(rich.content, "Weather details")
      assert_eq(rich.annotations.length(), 1)
      match rich.annotations[0] {
        @types.ResponseAnnotation::WebSearchResultCitation(
          title~,
          url~,
          start_index~,
          end_index~,
          ..
        ) => {
          assert_eq(title, "Tokyo Weather")
          assert_eq(url, "https://example.com/tokyo")
          assert_eq(start_index, 0)
          assert_eq(end_index, 15)
        }
        _ => fail("Expected citation to survive gateway pipeline")
      }
    }
    _ => fail("Expected RichText response with annotations")
  }
}

///|
test "parse_responses_api_result preserves Gemini grounding through Responses pipeline" {
  let gemini_body =
    #|{"candidates":[{"content":{"parts":[{"text":"Weather details"}],"role":"model"},"groundingMetadata":{"groundingChunks":[{"web":{"uri":"https://example.com/weather","title":"Weather Source"}}],"groundingSupports":[{"groundingChunkIndices":[0],"segment":{"text":"Weather","startIndex":0,"endIndex":7}}]},"finishReason":"STOP"}]}
  match
    parse_responses_api_result(
      GoogleGenerativeAI,
      gemini_body,
      model="gemini-2.0-flash",
    ) {
    @types.ModelResponse::RichText(rich) => {
      assert_eq(rich.content, "Weather details")
      assert_eq(rich.annotations.length(), 1)
      match rich.annotations[0] {
        @types.ResponseAnnotation::GeminiGroundingCitation(
          chunk_index~,
          chunk~,
          support~,
          cited_text~,
          start_index~,
          end_index~
        ) => {
          assert_eq(chunk_index, 0)
          assert_eq(cited_text, "Weather")
          match chunk {
            { "web": { "uri": String(url), "title": String(title), .. }, .. } => {
              assert_eq(title, "Weather Source")
              assert_eq(url, "https://example.com/weather")
            }
            _ => fail("Expected preserved grounding chunk")
          }
          match support {
            { "groundingChunkIndices": [Number(index, ..)], .. } =>
              assert_eq(index.to_int(), 0)
            _ => fail("Expected preserved grounding support")
          }
          assert_eq(start_index, 0)
          assert_eq(end_index, 7)
        }
        _ => fail("Expected grounding citation to survive gateway pipeline")
      }
    }
    _ => fail("Expected RichText response with Gemini annotations")
  }
}

///|
test "parse_responses_api_result reports native JSON parse errors" {
  match
    parse_responses_api_result(OpenAIResponses, "not json", model="gpt-4.1") {
    @types.ModelResponse::Failure(failure~) => {
      assert_eq(failure.type_, "parse_error")
      assert_eq(failure.message, "JSON parse error")
      assert_eq(failure.body, Some("not json"))
    }
    _ => fail("Expected structured parse failure")
  }
}

///|
test "transform_response_to_responses_json uses native Responses converters when available" {
  let anthropic_json = transform_response_to_responses_json(
    AnthropicMessages,
    "{\"id\":\"msg_tool\",\"model\":\"claude-sonnet-4-20250514\",\"content\":[{\"type\":\"tool_use\",\"id\":\"toolu_xyz789\",\"name\":\"lookup\",\"input\":{\"q\":\"moonbit\"}}],\"stop_reason\":\"tool_use\"}",
    model="claude-sonnet-4-20250514",
  )
  match anthropic_json {
    {
      "output": [
        {
          "type": "function_call",
          "id": String(id),
          "call_id": String(call_id),
          "name": "lookup",
          ..
        },
      ],
      ..
    } => {
      assert_eq(id, "fc_xyz789")
      assert_eq(call_id, "fc_xyz789")
    }
    _ =>
      fail(
        "Expected Anthropic tool_use to normalize into Responses function_call",
      )
  }

  let gemini_json = transform_response_to_responses_json(
    GoogleGenerativeAI,
    "{\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"functionCall\":{\"name\":\"get_weather\",\"args\":{\"city\":\"Tokyo\"}}}]},\"finishReason\":\"STOP\"}]}",
    model="gemini-2.0-flash",
  )
  match gemini_json {
    {
      "output": [
        {
          "type": "function_call",
          "id": String(id),
          "call_id": String(call_id),
          "name": "get_weather",
          ..
        },
      ],
      ..
    } => {
      assert_eq(id, "fc_get_weather_0")
      assert_eq(call_id, "fc_get_weather_0")
    }
    _ =>
      fail(
        "Expected Gemini functionCall to normalize into Responses function_call",
      )
  }

  let claude_json = transform_response_to_responses_json(
    ClaudeMcpServe,
    "{\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"file contents here\"}]}}",
    model="claude-code-tools",
  )
  match claude_json {
    {
      "output": [
        {
          "type": "message",
          "content": [{ "type": "output_text", "text": String(text), .. }],
          ..
        },
      ],
      ..
    } => assert_eq(text, "file contents here")
    _ =>
      fail(
        "Expected Claude MCP tools result to convert directly to Responses JSON",
      )
  }
}

///|
test "transform_response_to_responses_json preserves native and translated responses" {
  let native = transform_response_to_responses_json(
    OpenAIResponses,
    "{\"id\":\"resp_1\",\"model\":\"gpt-4.1\",\"output\":[{\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":\"Hi there!\"}]}]}",
    model="gpt-4.1",
  )
  match native {
    { "id": "resp_1", "output": Array(output), .. } =>
      assert_eq(output.length(), 1)
    _ => fail("Expected native Responses JSON passthrough")
  }

  let anthropic_body =
    #|{"id":"msg_cited","model":"claude-sonnet-4-20250514","content":[{"type":"text","text":"Weather details","citations":[{"type":"web_search_result_location","cited_text":"Weather details","encrypted_index":"enc_tokyo","title":"Tokyo Weather","url":"https://example.com/tokyo"}]}],"stop_reason":"end_turn"}
  let anthropic_json = transform_response_to_responses_json(
    AnthropicMessages,
    anthropic_body,
    model="claude-sonnet-4-20250514",
  )
  match anthropic_json {
    {
      "output": [
        {
          "type": "message",
          "content": [
            {
              "type": "output_text",
              "annotations": [
                {
                  "type": "web_search_result_location",
                  "title": "Tokyo Weather",
                  "url": "https://example.com/tokyo",
                  ..
                },
              ],
              ..
            },
          ],
          ..
        },
      ],
      ..
    } => ()
    _ => fail("Expected preserved Anthropic citation in Responses JSON")
  }

  let gemini_body =
    #|{"candidates":[{"content":{"parts":[{"text":"Weather details"}],"role":"model"},"groundingMetadata":{"groundingChunks":[{"web":{"uri":"https://example.com/weather","title":"Weather Source"}}],"groundingSupports":[{"groundingChunkIndices":[0],"segment":{"text":"Weather","startIndex":0,"endIndex":7}}]},"finishReason":"STOP"}]}
  let gemini_json = transform_response_to_responses_json(
    GoogleGenerativeAI,
    gemini_body,
    model="gemini-2.0-flash",
  )
  match gemini_json {
    {
      "output": [
        {
          "type": "message",
          "content": [
            {
              "type": "output_text",
              "annotations": [
                {
                  "type": "gemini_grounding",
                  "chunk": {
                    "web": {
                      "uri": "https://example.com/weather",
                      "title": "Weather Source",
                      ..
                    },
                    ..
                  },
                  ..
                },
              ],
              ..
            },
          ],
          ..
        },
      ],
      ..
    } => ()
    _ => fail("Expected preserved Gemini grounding in Responses JSON")
  }
}
