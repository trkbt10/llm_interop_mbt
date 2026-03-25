///|
/// Focused transform_request / transform_response coverage for same-surface and Codex paths

///|
fn smoke_ctx() -> @types.TransformContext {
  @types.TransformContext::default()
}

///|
test "transform_request: OpenAI same-surface renames max_tokens field" {
  let body = "{\"model\":\"o1-mini\",\"messages\":[],\"max_tokens\":42}"
  let result = transform_request(body, OpenAI, OpenAI, "o1-mini", {
    max_tokens: 0,
    max_tokens_field: "max_completion_tokens",
  })
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    { "max_completion_tokens": Number(max_tokens, ..), .. } => {
      assert_eq(max_tokens.to_int(), 42)
      assert_false(result.contains("\"max_tokens\""))
    }
    _ => fail("Expected renamed max token field")
  }
}

///|
test "transform_request: Anthropic same-surface injects default max_tokens" {
  let body = "{\"model\":\"claude\",\"messages\":[]}"
  let result = transform_request(body, Anthropic, Anthropic, "claude-sonnet", {
    max_tokens: 1024,
    max_tokens_field: "max_tokens",
  })
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    { "max_tokens": Number(max_tokens, ..), .. } =>
      assert_eq(max_tokens.to_int(), 1024)
    _ => fail("Expected injected max_tokens")
  }
}

///|
test "transform_request: Gemini same-surface is passthrough" {
  let body = "{\"contents\":[{\"role\":\"user\",\"parts\":[{\"text\":\"Hi\"}]}]}"
  assert_eq(
    transform_request(body, Gemini, Gemini, "gemini-2.5-flash", smoke_ctx()),
    body,
  )
}

///|
test "transform_request: OpenAI same-surface keeps existing renamed max token field" {
  let body = "{\"model\":\"o1-mini\",\"messages\":[],\"max_tokens\":42,\"max_completion_tokens\":64}"
  assert_eq(
    transform_request(body, OpenAI, OpenAI, "o1-mini", {
      max_tokens: 0,
      max_tokens_field: "max_completion_tokens",
    }),
    body,
  )
}

///|
test "transform_request: OpenAI to Codex extracts prompt and messages" {
  let body =
    #|{"model":"gpt-5-codex","messages":[{"role":"system","content":"Be terse"},{"role":"user","content":"Explain MoonBit"}],"reasoning_effort":"medium"}
  let result = transform_request(
    body,
    OpenAI,
    Codex,
    "gpt-5-codex",
    smoke_ctx(),
  )
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    {
      "prompt": String(prompt),
      "model": String(model),
      "effort": String(effort),
      "messages": Array(messages),
      ..
    } => {
      assert_true(prompt.contains("Be terse"))
      assert_true(prompt.contains("Explain MoonBit"))
      assert_eq(model, "gpt-5-codex")
      assert_eq(effort, "medium")
      assert_eq(messages.length(), 2)
    }
    _ => fail("Expected Codex protocol request")
  }
}

///|
test "transform_request: Codex to Anthropic routes through Responses bridge" {
  let body = "{\"prompt\":\"hello from codex\"}"
  let result = transform_request(body, Codex, Anthropic, "ignored", smoke_ctx())
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    {
      "messages": [{ "role": String("user"), "content": String(content), .. }],
      ..
    } => assert_eq(content, "hello from codex")
    _ => fail("Expected Anthropic request from Codex protocol bridge")
  }
}

///|
test "transform_request: Anthropic to OpenAI and Codex pivot correctly" {
  let anthropic_body =
    #|{"model":"claude","system":"Be concise","messages":[{"role":"user","content":"Hi"}]}
  let openai = transform_request(
    anthropic_body,
    Anthropic,
    OpenAI,
    "claude-sonnet",
    smoke_ctx(),
  )
  let openai_json : Json = @json.parse(openai) catch {
    _ => fail("parse error")
  }
  match openai_json {
    { "messages": Array(messages), .. } => assert_eq(messages.length(), 2)
    _ => fail("Expected OpenAI chat request")
  }

  let codex = transform_request(
    anthropic_body,
    Anthropic,
    Codex,
    "claude-sonnet",
    smoke_ctx(),
  )
  let codex_json : Json = @json.parse(codex) catch { _ => fail("parse error") }
  match codex_json {
    { "prompt": String(prompt), .. } => assert_true(prompt.contains("Hi"))
    _ => fail("Expected Codex prompt")
  }
}

///|
test "transform_request: Gemini to Anthropic pivots through OpenAI" {
  let body =
    #|{"contents":[{"role":"user","parts":[{"text":"Hello Gemini"}]}]}
  let result = transform_request(
    body,
    Gemini,
    Anthropic,
    "gemini-2.5-flash",
    smoke_ctx(),
  )
  let result_json : Json = @json.parse(result) catch {
    _ => fail("parse error")
  }
  match result_json {
    { "messages": [{ "role": String("user"), .. }], .. } => ()
    _ => fail("Expected Anthropic request")
  }
}

///|
test "transform_request: Gemini to OpenAI and Codex pivot correctly" {
  let body =
    #|{"contents":[{"role":"user","parts":[{"text":"Hello Gemini"}]}]}
  let openai = transform_request(
    body,
    Gemini,
    OpenAI,
    "gemini-2.5-flash",
    smoke_ctx(),
  )
  let openai_json : Json = @json.parse(openai) catch {
    _ => fail("parse error")
  }
  match openai_json {
    { "messages": Array(messages), .. } => assert_eq(messages.length(), 1)
    _ => fail("Expected OpenAI chat request")
  }

  let codex = transform_request(
    body,
    Gemini,
    Codex,
    "gemini-2.5-flash",
    smoke_ctx(),
  )
  let codex_json : Json = @json.parse(codex) catch { _ => fail("parse error") }
  match codex_json {
    { "prompt": String(prompt), .. } =>
      assert_true(prompt.contains("Hello Gemini"))
    _ => fail("Expected Codex prompt")
  }
}

///|
test "transform_request: OpenAI to Anthropic preserves structured output and tool_choice via Responses bridge" {
  let body =
    #|{"model":"claude-sonnet-4-6","messages":[{"role":"system","content":"Return JSON only."},{"role":"user","content":"Look up the URL"}],"tools":[{"type":"function","function":{"name":"lookup","description":"Lookup URL","parameters":{"type":"object","properties":{"label":{"type":"string"}},"required":["label"]}}}],"tool_choice":{"type":"function","function":{"name":"lookup"}},"response_format":{"type":"json_schema","json_schema":{"name":"resp","schema":{"type":"object","properties":{"url":{"type":"string"}},"required":["url"]},"strict":true}}}
  let result = transform_request(
    body,
    OpenAI,
    Anthropic,
    "claude-sonnet-4-6",
    smoke_ctx(),
  )
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    {
      "system": "Return JSON only.",
      "messages": Array(messages),
      "tools": Array(tools),
      "tool_choice": { "type": String("tool"), "name": String("lookup"), .. },
      "output_config": { "format": { "type": "json_schema", .. }, .. },
      ..
    } => {
      assert_eq(messages.length(), 1)
      assert_eq(tools.length(), 1)
    }
    _ => fail("Expected Anthropic request translated via Responses contract")
  }
}

///|
test "transform_request: Anthropic to Gemini and Codex to Codex are covered" {
  let anthropic_body =
    #|{"model":"claude","system":"Be concise","messages":[{"role":"user","content":"Hi"}]}
  let gemini = transform_request(
    anthropic_body,
    Anthropic,
    Gemini,
    "claude-sonnet",
    smoke_ctx(),
  )
  let gemini_json : Json = @json.parse(gemini) catch {
    _ => fail("parse error")
  }
  match gemini_json {
    { "contents": Array(contents), .. } => assert_eq(contents.length(), 1)
    _ => fail("Expected Gemini request")
  }

  let codex_body = "{\"prompt\":\"hello from codex\"}"
  assert_eq(
    transform_request(codex_body, Codex, Codex, "ignored", smoke_ctx()),
    codex_body,
  )
}

///|
test "panic transform_request rejects non-object OpenAI same-surface normalization bodies" {
  ignore(
    transform_request("[]", OpenAI, OpenAI, "o1-mini", {
      max_tokens: 0,
      max_tokens_field: "max_completion_tokens",
    }),
  )
}

///|
test "panic transform_request rejects invalid JSON OpenAI same-surface normalization bodies" {
  ignore(
    transform_request("{", OpenAI, OpenAI, "o1-mini", {
      max_tokens: 0,
      max_tokens_field: "max_completion_tokens",
    }),
  )
}

///|
test "panic transform_request rejects non-object Anthropic same-surface normalization bodies" {
  ignore(
    transform_request("[]", Anthropic, Anthropic, "claude", {
      max_tokens: 128,
      max_tokens_field: "max_tokens",
    }),
  )
}

///|
test "panic transform_request rejects invalid JSON Anthropic same-surface normalization bodies" {
  ignore(
    transform_request("{", Anthropic, Anthropic, "claude", {
      max_tokens: 128,
      max_tokens_field: "max_tokens",
    }),
  )
}

///|
test "transform_response: Anthropic error to Anthropic stays unchanged" {
  let body =
    #|{"type":"error","error":{"type":"invalid_request_error","message":"bad request"}}
  assert_eq(transform_response(body, Anthropic, Anthropic), body)
}

///|
test "panic transform_response rejects invalid JSON for cross-surface translation" {
  ignore(transform_response("{", OpenAI, Gemini))
}

///|
test "panic transform_response rejects invalid JSON when Codex translation is required" {
  ignore(transform_response("{", OpenAI, Codex))
}

///|
test "transform_response: invalid JSON stays unchanged only for identity paths" {
  assert_eq(transform_response("{", OpenAI, OpenAI), "{")
}

///|
test "transform_response: incomplete Anthropic error payload preserves top-level error body" {
  let body = "{\"type\":\"error\"}"
  let json : Json = @json.parse(transform_response(body, Anthropic, OpenAI)) catch {
    _ => fail("parse error")
  }
  match json {
    { "error": { "message": String(message), "type": String(kind), .. }, .. } => {
      assert_eq(message, "{\"type\":\"error\"}")
      assert_eq(kind, "error")
    }
    _ => fail("Expected normalized OpenAI error")
  }
}

///|
test "transform_response: Anthropic to OpenAI chat preserves url_citation subset" {
  let body =
    #|{"id":"msg_cited","model":"claude-sonnet-4-20250514","content":[{"type":"text","text":"Weather details","citations":[{"type":"web_search_result_location","cited_text":"Weather details","encrypted_index":"enc_tokyo","title":"Tokyo Weather","url":"https://example.com/tokyo"}]}],"stop_reason":"end_turn"}
  let result = transform_response(body, Anthropic, OpenAI)
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    { "choices": [{ "message": message, .. }], .. } =>
      match message {
        Object(fields) => {
          match fields.get("content") {
            Some(String(content)) => assert_eq(content, "Weather details")
            _ => fail("Expected transformed chat text content")
          }
          match fields.get("annotations") {
            Some(Array(annotations)) => {
              assert_eq(annotations.length(), 1)
              match annotations[0] {
                {
                  "type": String("url_citation"),
                  "url_citation": {
                    "title": String(title),
                    "url": String(url),
                    "start_index": Number(start_index, ..),
                    "end_index": Number(end_index, ..),
                    ..
                  },
                  ..
                } => {
                  assert_eq(title, "Tokyo Weather")
                  assert_eq(url, "https://example.com/tokyo")
                  assert_eq(start_index.to_int(), 0)
                  assert_eq(end_index.to_int(), 15)
                }
                _ => fail("Expected url_citation annotation")
              }
            }
            _ => fail("Expected transformed annotations")
          }
        }
        _ => fail("Expected chat message object")
      }
    _ => fail("Expected OpenAI chat response")
  }
  assert_false(result.contains("\"web_search_result_location\""))
}

///|
test "transform_response: Gemini to OpenAI chat preserves url_citation subset" {
  let body =
    #|{"candidates":[{"content":{"parts":[{"text":"Weather details"}],"role":"model"},"groundingMetadata":{"groundingChunks":[{"web":{"uri":"https://example.com/weather","title":"Weather Source"}}],"groundingSupports":[{"groundingChunkIndices":[0],"segment":{"text":"Weather","startIndex":0,"endIndex":7}}]},"finishReason":"STOP"}]}
  let result = transform_response(body, Gemini, OpenAI)
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    { "choices": [{ "message": message, .. }], .. } =>
      match message {
        {
          "content": String(content),
          "annotations": [
            {
              "type": String("url_citation"),
              "url_citation": {
                "title": String(title),
                "url": String(url),
                "start_index": Number(start_index, ..),
                "end_index": Number(end_index, ..),
                ..
              },
              ..
            },
          ],
          ..
        } => {
          assert_eq(content, "Weather details")
          assert_eq(title, "Weather Source")
          assert_eq(url, "https://example.com/weather")
          assert_eq(start_index.to_int(), 0)
          assert_eq(end_index.to_int(), 7)
        }
        _ => fail("Expected grounded chat message")
      }
    _ => fail("Expected OpenAI chat response")
  }
}

///|
test "panic transform_response rejects Anthropic annotations without OpenAI chat carrier" {
  ignore(
    transform_response(
      "{\"id\":\"msg_page\",\"model\":\"claude\",\"content\":[{\"type\":\"text\",\"text\":\"MoonBit\",\"citations\":[{\"type\":\"page_location\",\"cited_text\":\"MoonBit\",\"document_index\":0,\"document_title\":\"Spec\",\"file_id\":\"file_spec\",\"start_page_number\":1,\"end_page_number\":1}]}],\"stop_reason\":\"end_turn\"}",
      Anthropic,
      OpenAI,
    ),
  )
}

///|
test "transform_response: OpenAI chat url_citation subset becomes Gemini grounding metadata" {
  let result = transform_response(
    "{\"id\":\"chatcmpl-1\",\"model\":\"gpt-4.1\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"hi\",\"annotations\":[{\"type\":\"url_citation\",\"url_citation\":{\"title\":\"Docs\",\"url\":\"https://example.com\",\"start_index\":0,\"end_index\":2}}]},\"finish_reason\":\"stop\"}]}",
    OpenAI,
    Gemini,
  )
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    {
      "candidates": [
        {
          "groundingMetadata": {
            "groundingChunks": [
              { "web": { "uri": String(url), "title": String(title), .. }, .. },
            ],
            "groundingSupports": [
              {
                "segment": {
                  "text": String(text),
                  "startIndex": Number(start, ..),
                  "endIndex": Number(end_, ..),
                  ..
                },
                ..
              },
            ],
            ..
          },
          ..
        },
      ],
      ..
    } => {
      assert_eq(url, "https://example.com")
      assert_eq(title, "Docs")
      assert_eq(text, "hi")
      assert_eq(start.to_int(), 0)
      assert_eq(end_.to_int(), 2)
    }
    _ => fail("Expected Gemini grounding metadata")
  }
}

///|
test "transform_response: Codex to OpenAI produces chat completion" {
  let body =
    #|[{"method":"item/agentMessage/delta","params":{"delta":"Hello from Codex"}},{"method":"turn/completed","params":{"turn":{"id":"turn_1","status":"completed"}}}]
  let result = transform_response(body, Codex, OpenAI)
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    { "choices": [{ "message": { "content": String(content), .. }, .. }], .. } =>
      assert_eq(content, "Hello from Codex")
    _ => fail("Expected OpenAI chat response")
  }
}

///|
test "transform_response: Codex to Anthropic and Gemini route through Responses bridge" {
  let body =
    #|[{"method":"item/agentMessage/delta","params":{"delta":"Hello from Codex"}},{"method":"turn/completed","params":{"turn":{"id":"turn_1","status":"completed"}}}]
  let anthropic_json : Json = @json.parse(
    transform_response(body, Codex, Anthropic),
  ) catch {
    _ => fail("parse error")
  }
  match anthropic_json {
    { "content": [{ "type": String("text"), "text": String(text), .. }], .. } =>
      assert_eq(text, "Hello from Codex")
    _ => fail("Expected Anthropic response")
  }

  let gemini_json : Json = @json.parse(transform_response(body, Codex, Gemini)) catch {
    _ => fail("parse error")
  }
  match gemini_json {
    { "candidates": Array(candidates), .. } => assert_eq(candidates.length(), 1)
    _ => fail("Expected Gemini response")
  }
}

///|
test "transform_response: OpenAI text responses become Codex event arrays via Responses bridge" {
  let openai_body =
    #|{"id":"chatcmpl-1","object":"chat.completion","model":"gpt-4","choices":[{"index":0,"message":{"role":"assistant","content":"Hello"},"finish_reason":"stop"}]}
  let result = transform_response(openai_body, OpenAI, Codex)
  let json : Json = @json.parse(result) catch { _ => fail("parse error") }
  match json {
    Array(events) => assert_true(events.length() >= 2)
    _ => fail("Expected Codex event array")
  }
  let round_trip = @codex.response_to_chat(result)
  let round_trip_json : Json = @json.parse(round_trip) catch {
    _ => fail("round-trip parse error")
  }
  match round_trip_json {
    { "choices": [{ "message": { "content": String(content), .. }, .. }], .. } =>
      assert_eq(content, "Hello")
    _ => fail("Expected OpenAI chat round-trip")
  }
}

///|
test "panic transform_response rejects tool-calling responses when targeting Codex" {
  ignore(
    transform_response(
      "{\"id\":\"chatcmpl-1\",\"object\":\"chat.completion\",\"model\":\"gpt-4\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"tool_calls\":[{\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"lookup\",\"arguments\":\"{}\"}}],\"content\":null},\"finish_reason\":\"tool_calls\"}]}",
      OpenAI,
      Codex,
    ),
  )
}

///|
test "transform_response: Codex passthrough to Codex" {
  let body = "[{\"method\":\"turn/completed\",\"params\":{\"turn\":{\"id\":\"t\",\"status\":\"completed\"}}}]"
  assert_eq(transform_response(body, Codex, Codex), body)
}
