///|
test "OpenAI chat contract builders create canonical response shapes" {
  let tool_calls = [
    build_tool_call_json("call_1", "lookup", { "q": "moonbit" }),
  ]
  let choice = build_chat_choice(0, "Preface", tool_calls, annotations=[
    {
      "type": "url_citation",
      "url_citation": {
        "title": "Docs",
        "url": "https://example.com/docs",
        "start_index": 0,
        "end_index": 4,
      },
    },
  ])
  match choice {
    {
      "index": Number(index, ..),
      "message": {
        "role": "assistant",
        "content": "Preface",
        "tool_calls": Array(encoded_calls),
        "annotations": Array(encoded_annotations),
        ..
      },
      "finish_reason": "tool_calls",
      ..
    } => {
      assert_eq(index.to_int(), 0)
      assert_eq(encoded_calls.length(), 1)
      assert_eq(encoded_annotations.length(), 1)
    }
    _ => fail("Expected OpenAI chat choice")
  }

  let response = build_chat_response("chatcmpl_1", "gpt-4o", [choice])
  match @json.parse(response) {
    { "id": "chatcmpl_1", "model": "gpt-4o", "choices": Array(choices), .. } =>
      assert_eq(choices.length(), 1)
    _ => fail("Expected chat completion envelope")
  }
}

///|
test "OpenAI chat annotation builder preserves representable citation subset" {
  let annotations = chat_annotations_from_response_annotations([
    @types.ResponseAnnotation::url_citation(
      url="https://example.com/docs",
      title=Some("Docs"),
      start_index=0,
      end_index=4,
    ),
    @types.ResponseAnnotation::web_search_result_citation(
      cited_text="MoonBit",
      encrypted_index="enc_1",
      title="MoonBit Search",
      url="https://example.com/search",
      start_index=5,
      end_index=12,
    ),
    @types.ResponseAnnotation::gemini_grounding_citation(
      chunk_index=2,
      chunk={
        "retrievedContext": {
          "uri": "https://example.com/retrieved",
          "title": "Retrieved Source",
          "text": "MoonBit docs",
        },
      },
      support={
        "groundingChunkIndices": [2],
        "segment": { "text": "docs", "startIndex": 13, "endIndex": 17 },
      },
      cited_text="docs",
      start_index=13,
      end_index=17,
    ),
  ])
  assert_eq(annotations.length(), 3)
  match annotations[0] {
    {
      "type": "url_citation",
      "url_citation": {
        "title": String(title),
        "url": String(url),
        "start_index": Number(start_index, ..),
        "end_index": Number(end_index, ..),
        ..
      },
      ..
    } => {
      assert_eq(title, "Docs")
      assert_eq(url, "https://example.com/docs")
      assert_eq(start_index.to_int(), 0)
      assert_eq(end_index.to_int(), 4)
    }
    _ => fail("Expected direct url citation")
  }
  match annotations[1] {
    {
      "type": "url_citation",
      "url_citation": {
        "title": String(title),
        "url": String(url),
        "start_index": Number(start_index, ..),
        "end_index": Number(end_index, ..),
        ..
      },
      ..
    } => {
      assert_eq(title, "MoonBit Search")
      assert_eq(url, "https://example.com/search")
      assert_eq(start_index.to_int(), 5)
      assert_eq(end_index.to_int(), 12)
    }
    _ => fail("Expected web-search citation down-convert")
  }
  match annotations[2] {
    {
      "type": "url_citation",
      "url_citation": {
        "title": String(title),
        "url": String(url),
        "start_index": Number(start_index, ..),
        "end_index": Number(end_index, ..),
        ..
      },
      ..
    } => {
      assert_eq(title, "Retrieved Source")
      assert_eq(url, "https://example.com/retrieved")
      assert_eq(start_index.to_int(), 13)
      assert_eq(end_index.to_int(), 17)
    }
    _ => fail("Expected Gemini grounding down-convert")
  }
}

///|
test "panic OpenAI chat annotation builder rejects lossy provider-specific annotations" {
  ignore(
    chat_annotations_from_response_annotations([
      @types.ResponseAnnotation::document_page_citation(
        cited_text="MoonBit",
        document_index=0,
        document_title="Spec",
        file_id="file_spec",
        start_page_number=1,
        end_page_number=1,
        start_index=0,
        end_index=7,
      ),
    ]),
  )
}

///|
test "panic OpenAI chat response bridge rejects tool traces without carrier" {
  ignore(
    model_response_to_chat_response(
      @types.ModelResponse::RichText(
        @types.RichTextResponse::from_parts(
          content="Searching...",
          content_parts=[@types.ResponseContentPart::OutputText("Searching...")],
          tool_traces=[
            @types.ToolCallTrace::new(
              id="ws_1",
              name=@types.web_search_tool_name(),
              kind=@types.ToolCallKind::WebSearch,
              statuses=[@types.ToolCallStatus::Completed],
              arguments={ "query": "moonbit" },
            ),
          ],
        ),
      ),
      id="chatcmpl_1",
      model="gpt-4.1",
    ),
  )
}

///|
test "panic OpenAI chat contract request bridge rejects lossy assistant content and tool_choice" {
  ignore(
    chat_request_to_responses_request(
      "{\"model\":\"gpt-4.1\",\"messages\":[{\"role\":\"assistant\",\"content\":[{\"type\":\"image_url\",\"image_url\":{\"url\":\"https://example.com/cat.png\"}}]}]}",
    ),
  )
  ignore(
    chat_request_to_responses_request(
      "{\"model\":\"gpt-4.1\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"tool_choice\":{\"type\":\"custom\",\"name\":\"lookup\"}}",
    ),
  )
}

///|
test "OpenAI chat contract request bridge preserves instructions, tools, tool_choice, and response_format" {
  let request = chat_request_to_responses_request(
    "{\"model\":\"gpt-4.1\",\"messages\":[{\"role\":\"system\",\"content\":\"Return JSON only.\"},{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"Look up the URL\"},{\"type\":\"image_url\",\"image_url\":{\"url\":\"https://example.com/cat.png\",\"detail\":\"high\"}}]}],\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"lookup\",\"description\":\"Lookup URL\",\"parameters\":{\"type\":\"object\",\"properties\":{\"label\":{\"type\":\"string\"}},\"required\":[\"label\"]}}}],\"tool_choice\":{\"type\":\"function\",\"function\":{\"name\":\"lookup\"}},\"reasoning_effort\":\"medium\",\"response_format\":{\"type\":\"json_schema\",\"json_schema\":{\"name\":\"resp\",\"schema\":{\"type\":\"object\",\"properties\":{\"url\":{\"type\":\"string\"}},\"required\":[\"url\"]},\"strict\":true}}}",
  )
  match request {
    {
      "model": "gpt-4.1",
      "instructions": "Return JSON only.",
      "input": Array(input),
      "tools": Array(tools),
      "tool_choice": { "type": "function", "name": "lookup", .. },
      "reasoning": { "effort": "medium", .. },
      "text": { "format": { "type": "json_schema", .. }, .. },
      ..
    } => {
      assert_eq(input.length(), 1)
      assert_eq(tools.length(), 1)
      match input[0] {
        { "role": "user", "content": Array(parts), .. } =>
          assert_eq(parts.length(), 2)
        _ => fail("Expected Responses user input item")
      }
      match tools[0] {
        {
          "type": "function",
          "name": "lookup",
          "description": "Lookup URL",
          ..
        } => ()
        _ => fail("Expected flattened Responses function tool")
      }
    }
    _ => fail("Expected canonical Responses request")
  }
}

///|
test "OpenAI chat contract response bridge preserves tool calls and failures" {
  let success = model_response_to_chat_response(
    @types.ModelResponse::ToolCallsWithContent(
      tool_calls=[
        @types.ToolCallRequest::new(id="call_1", name="lookup", arguments={
          "label": "interop",
        }),
      ],
      rich=@types.RichTextResponse::from_parts(content="Let me check.", content_parts=[
        @types.ResponseContentPart::OutputText("Let me check."),
      ]),
    ),
    id="chatcmpl_1",
    model="gpt-4.1",
  )
  match @json.parse(success) {
    {
      "id": "chatcmpl_1",
      "choices": [
        {
          "message": {
            "content": "Let me check.",
            "tool_calls": Array(tool_calls),
            ..
          },
          "finish_reason": "tool_calls",
          ..
        },
      ],
      ..
    } => assert_eq(tool_calls.length(), 1)
    _ => fail("Expected OpenAI chat completion with tool calls")
  }

  let failure = model_response_to_chat_response(
    @types.ModelResponse::Failure(
      failure=@types.ModelFailure::new(
        type_="invalid_request_error",
        message="bad request",
      ),
    ),
    id="ignored",
    model="ignored",
  )
  match @json.parse(failure) {
    {
      "error": { "type": "invalid_request_error", "message": "bad request", .. },
      ..
    } => ()
    _ => fail("Expected canonical OpenAI error carrier")
  }
}
