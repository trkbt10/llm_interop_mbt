///|
/// Types package tests

///|
test "ToolCallRequest::new creates instance" {
  let call = ToolCallRequest::new(id="call_123", name="get_weather", arguments={
    "city": "Tokyo",
  })
  inspect(call.id, content="call_123")
  inspect(call.name, content="get_weather")
  assert_eq(call.kind, ToolCallKind::Function)
}

///|
test "ToolCallRequest::default creates empty instance" {
  let call = ToolCallRequest::default()
  inspect(call.id, content="")
  inspect(call.name, content="")
}

///|
test "ToolCallRequest::builtin creates builtin instance" {
  let call = ToolCallRequest::builtin(
    id="mcp_123",
    type_="mcp_call",
    payload={ "server_label": "docs", "arguments": "{\"topic\":\"MoonBit\"}" },
    name="lookup_docs",
  )
  assert_eq(call.kind, ToolCallKind::Builtin(builtin_type="mcp_call"))
  inspect(call.id, content="mcp_123")
  inspect(call.name, content="lookup_docs")
  match call.arguments {
    { "server_label": String(label), .. } => assert_eq(label, "docs")
    _ => fail("Expected builtin payload")
  }
}

///|
test "ToolCallRequest::web_search supports queries array without query" {
  let call = ToolCallRequest::web_search(
    id="ws_123",
    queries=Some(["moonbit", "responses api"]),
  )
  assert_eq(call.kind, ToolCallKind::WebSearch)
  match call.arguments {
    { "queries": Array(queries), .. } => assert_eq(queries.length(), 2)
    _ => fail("Expected queries array")
  }
  match build_web_search_action(call.arguments) {
    { "type": String("search"), "queries": Array(queries), .. } =>
      assert_eq(queries.length(), 2)
    _ => fail("Expected search action with queries")
  }
}

///|
test "ToolDefinition::new creates instance" {
  let tool = ToolDefinition::new(name="search", description="Search the web", parameters={
    "type": "object",
  })
  inspect(tool.name, content="search")
  inspect(tool.description, content="Search the web")
  assert_eq(tool.kind, ToolDefinitionKind::Function)
}

///|
test "ToolDefinition::web_search_preview creates builtin instance" {
  let tool = ToolDefinition::web_search_preview(
    search_context_size=Some("medium"),
    user_location_country=Some("US"),
  )
  inspect(tool.name, content="web_search")
  match tool.kind {
    ToolDefinitionKind::WebSearchPreview(
      search_context_size~,
      user_location_country~
    ) => {
      assert_eq(search_context_size, Some("medium"))
      assert_eq(user_location_country, Some("US"))
    }
    _ => fail("Expected WebSearchPreview kind")
  }
}

///|
test "ToolDefinition::builtin creates provider builtin instance" {
  let tool = ToolDefinition::builtin(
    type_="code_execution_20250825",
    name="code_execution",
    config={ "allowed_callers": Json::array([Json::string("direct")]) },
  )
  inspect(tool.name, content="code_execution")
  match tool.kind {
    ToolDefinitionKind::Builtin(builtin_type~, config~) => {
      assert_eq(builtin_type, "code_execution_20250825")
      match config {
        { "allowed_callers": Array(values), .. } =>
          assert_eq(values.length(), 1)
        _ => fail("Expected config payload")
      }
    }
    _ => fail("Expected Builtin kind")
  }
}

///|
test "build_json_schema creates valid schema" {
  let schema = build_json_schema(
    type_="object",
    properties={ "name": { "type": "string" } },
    required=["name"],
  )
  match schema {
    { "type": "object", "properties": Object(_), "required": Array(_), .. } =>
      ()
    _ => fail("Expected valid schema")
  }
}

///|
test "ContentPart enum covers all multimodal types" {
  // Verify all ContentPart variants can be constructed
  let parts : Array[ContentPart] = [
    ContentPart::Text("hello"),
    ContentPart::ImageUrl(url="https://img.png", detail=Some("auto")),
    ContentPart::ImageBase64(data="abc", media_type="image/png"),
    ContentPart::Audio(data="base64audio", format="wav"),
    ContentPart::Document(
      data="base64pdf",
      media_type="application/pdf",
      title=Some("doc.pdf"),
    ),
    ContentPart::FileRef(file_id="file_abc", media_type=Some("application/pdf")),
    ContentPart::FileUrl(url="https://example.com/doc.pdf"),
    ContentPart::Video(data="base64video", media_type="video/mp4"),
  ]
  inspect(parts.length(), content="8")
}

///|
test "ResponseContentPart enum covers all output types" {
  let parts : Array[ResponseContentPart] = [
    ResponseContentPart::OutputText("hello"),
    ResponseContentPart::OutputImage(url="https://img.png"),
    ResponseContentPart::Refusal("cannot help"),
    ResponseContentPart::Thinking(text="let me think..."),
    ResponseContentPart::RedactedThinking(data="encrypted..."),
    ResponseContentPart::CodeExecution(language="python", code="print(1)"),
    ResponseContentPart::CodeResult(outcome="OUTCOME_OK", output="1"),
    ResponseContentPart::AudioOutput(data="base64audio", transcript="hello"),
  ]
  inspect(parts.length(), content="8")
}

///|
test "ModelFailure constructors preserve structured fields" {
  let generic = ModelFailure::new(
    type_="invalid_request_error",
    message="bad request",
    code=Some(400),
    retry_after=None,
    payload=Some({ "field": "messages" }),
    body=Some("{\"error\":true}"),
  )
  assert_eq(generic.type_, "invalid_request_error")
  assert_eq(generic.message, "bad request")
  assert_eq(generic.code, Some(400))
  assert_eq(generic.body, Some("{\"error\":true}"))
  match generic.payload {
    Some({ "field": String("messages"), .. }) => ()
    _ => fail("Expected preserved payload")
  }

  let rate_limited = ModelFailure::rate_limited(
    retry_after=60,
    body=Some("rate limited"),
  )
  assert_eq(rate_limited.type_, "rate_limit_error")
  assert_eq(rate_limited.code, Some(429))
  assert_eq(rate_limited.retry_after, Some(60))
  assert_eq(rate_limited.body, Some("rate limited"))

  let parse_error = ModelFailure::parse_error(
    message="invalid provider response",
    payload=Some({ "provider": "gemini" }),
    body=Some("{bad"),
  )
  assert_eq(parse_error.type_, "parse_error")
  assert_eq(parse_error.message, "invalid provider response")
  assert_eq(parse_error.body, Some("{bad"))
  match parse_error.payload {
    Some({ "provider": String("gemini"), .. }) => ()
    _ => fail("Expected parse-error payload")
  }

  match ModelResponse::Failure(failure=parse_error).as_failure() {
    Some(failure) => assert_eq(failure.type_, "parse_error")
    None => fail("Expected explicit failure conversion")
  }
  match ModelResponse::ModelError("legacy error").as_failure() {
    Some(failure) => {
      assert_eq(failure.type_, "error")
      assert_eq(failure.message, "legacy error")
    }
    None => fail("Expected legacy ModelError conversion")
  }
  match ModelResponse::RateLimited(retry_after=7).as_failure() {
    Some(failure) => {
      assert_eq(failure.type_, "rate_limit_error")
      assert_eq(failure.retry_after, Some(7))
    }
    None => fail("Expected legacy RateLimited conversion")
  }
  match ModelResponse::Text("ok").as_failure() {
    None => ()
    Some(_) => fail("Expected text response to stay non-failure")
  }

  let openai_json = generic.to_openai_error_json()
  match openai_json {
    {
      "error": {
        "type": String(type_),
        "message": String(message),
        "code": Number(code, ..),
        ..
      },
      ..
    } => {
      assert_eq(type_, "invalid_request_error")
      assert_eq(message, "bad request")
      assert_eq(code.to_int(), 400)
    }
    _ => fail("Expected OpenAI error JSON")
  }

  let anthropic_json = generic.to_anthropic_error_json()
  match anthropic_json {
    {
      "type": String("error"),
      "error": { "type": String(type_), "message": String(message), .. },
      ..
    } => {
      assert_eq(type_, "invalid_request_error")
      assert_eq(message, "bad request")
    }
    _ => fail("Expected Anthropic error JSON")
  }

  let gemini_json = rate_limited.to_gemini_error_json()
  match gemini_json {
    {
      "error": {
        "status": String(status),
        "code": Number(code, ..),
        "message": String(message),
        ..
      },
      ..
    } => {
      assert_eq(status, "RESOURCE_EXHAUSTED")
      assert_eq(code.to_int(), 429)
      assert_eq(message, "Rate limited")
    }
    _ => fail("Expected Gemini error JSON")
  }
}

///|
test "RichTextResponse with content_parts" {
  let rich = RichTextResponse::new(
    content="Hello",
    content_parts=Some([
      ResponseContentPart::OutputText("Hello"),
      ResponseContentPart::OutputImage(url="https://img.png"),
    ]),
  )
  inspect(rich.content, content="Hello")
  match rich.content_parts {
    Some(parts) => inspect(parts.length(), content="2")
    None => fail("Expected content_parts")
  }
}

///|
test "RichTextResponse::from_parts preserves structure only when needed" {
  let plain = RichTextResponse::from_parts(content="Hello", content_parts=[
    ResponseContentPart::OutputText("Hello"),
  ])
  let structured = RichTextResponse::from_parts(content="Hello world", content_parts=[
    ResponseContentPart::OutputText("Hello"),
    ResponseContentPart::OutputText(" world"),
  ])
  assert_eq(plain.content_parts, None)
  match structured.content_parts {
    Some(parts) => assert_eq(parts.length(), 2)
    None => fail("Expected structured content parts")
  }
}

///|
test "GenerationParams::from_openai extracts full parameter matrix" {
  let params = GenerationParams::from_openai({
    "max_completion_tokens": 321,
    "temperature": 0.7,
    "top_p": 0.95,
    "top_k": 40,
    "stop": "END",
    "stream": false,
    "reasoning_effort": "medium",
    "response_format": {
      "type": "json_schema",
      "json_schema": {
        "name": "answer",
        "description": "Structured answer",
        "schema": { "type": "object" },
        "strict": true,
      },
    },
  })
  match params.max_tokens {
    Number(value, ..) => assert_eq(value.to_int(), 321)
    _ => fail("Expected max_tokens")
  }
  match params.temperature {
    Number(value, ..) => assert_eq(value, 0.7)
    _ => fail("Expected temperature")
  }
  match params.top_p {
    Number(value, ..) => assert_eq(value, 0.95)
    _ => fail("Expected top_p")
  }
  match params.top_k {
    Number(value, ..) => assert_eq(value.to_int(), 40)
    _ => fail("Expected top_k")
  }
  match params.stop {
    Array(values) => {
      assert_eq(values.length(), 1)
      assert_eq(values[0], Json::string("END"))
    }
    _ => fail("Expected stop array")
  }
  match params.stream {
    False => ()
    _ => fail("Expected stream=false")
  }
  match params.reasoning_effort {
    String(value) => assert_eq(value, "medium")
    _ => fail("Expected reasoning_effort")
  }
  assert_eq(
    params.response_format,
    Some(
      ResponseFormat::JsonSchema(
        name=Some("answer"),
        schema={ "type": "object" },
        description=Some("Structured answer"),
        strict=Some(true),
      ),
    ),
  )
  match params.response_format_context {
    Some(ctx) => {
      assert_eq(ctx.surface, "openai_chat")
      assert_eq(ctx.raw, {
        "type": "json_schema",
        "json_schema": {
          "name": "answer",
          "description": "Structured answer",
          "schema": { "type": "object" },
          "strict": true,
        },
      })
    }
    None => fail("Expected OpenAI response format context")
  }
}

///|
test "GenerationParams::from_anthropic and from_gemini extract provider fields" {
  let anthropic = GenerationParams::from_anthropic({
    "max_tokens": 512,
    "temperature": 0.2,
    "top_p": 0.8,
    "top_k": 12,
    "stop_sequences": ["END", "STOP"],
    "stream": true,
    "output_config": {
      "format": {
        "type": "json_schema",
        "schema": { "type": "object", "properties": {} },
      },
    },
  })
  match anthropic.stop {
    Array(values) => assert_eq(values.length(), 2)
    _ => fail("Expected anthropic stop sequences")
  }
  match anthropic.stream {
    True => ()
    _ => fail("Expected anthropic stream=true")
  }
  assert_eq(
    anthropic.response_format,
    Some(
      ResponseFormat::JsonSchema(
        name=None,
        schema={ "type": "object", "properties": {} },
        description=None,
        strict=None,
      ),
    ),
  )
  match anthropic.response_format_context {
    Some(ctx) => {
      assert_eq(ctx.surface, "anthropic")
      assert_eq(ctx.raw, {
        "format": {
          "type": "json_schema",
          "schema": { "type": "object", "properties": {} },
        },
      })
    }
    None => fail("Expected anthropic response format context")
  }
  let gemini = GenerationParams::from_gemini({
    "generationConfig": {
      "maxOutputTokens": 128,
      "temperature": 0.6,
      "topP": 0.9,
      "topK": 24,
      "stopSequences": ["DONE"],
      "responseMimeType": "application/json",
      "responseJsonSchema": { "type": "object", "required": ["answer"] },
    },
  })
  match gemini.max_tokens {
    Number(value, ..) => assert_eq(value.to_int(), 128)
    _ => fail("Expected gemini max_tokens")
  }
  match gemini.stop {
    Array(values) => assert_eq(values.length(), 1)
    _ => fail("Expected gemini stop sequences")
  }
  assert_eq(
    gemini.response_format,
    Some(
      ResponseFormat::JsonSchema(
        name=None,
        schema={ "type": "object", "required": ["answer"] },
        description=None,
        strict=None,
      ),
    ),
  )
  match gemini.response_format_context {
    Some(ctx) => {
      assert_eq(ctx.surface, "gemini")
      assert_eq(ctx.raw, {
        "responseMimeType": "application/json",
        "responseJsonSchema": { "type": "object", "required": ["answer"] },
      })
    }
    None => fail("Expected gemini response format context")
  }
}

///|
test "GenerationParams::from_responses extracts structured output config" {
  let params = GenerationParams::from_responses({
    "max_output_tokens": 222,
    "temperature": 0.2,
    "top_p": 0.7,
    "reasoning": { "effort": "low" },
    "text": { "format": { "type": "json_object" } },
  })
  match params.max_tokens {
    Number(value, ..) => assert_eq(value.to_int(), 222)
    _ => fail("Expected responses max_output_tokens")
  }
  match params.temperature {
    Number(value, ..) => assert_eq(value, 0.2)
    _ => fail("Expected responses temperature")
  }
  match params.top_p {
    Number(value, ..) => assert_eq(value, 0.7)
    _ => fail("Expected responses top_p")
  }
  match params.reasoning_effort {
    String(value) => assert_eq(value, "low")
    _ => fail("Expected responses reasoning.effort")
  }
  assert_eq(params.response_format, Some(ResponseFormat::JsonObject))
  match params.response_format_context {
    Some(ctx) => {
      assert_eq(ctx.surface, "openai_responses")
      assert_eq(ctx.raw, { "type": "json_object" })
    }
    None => fail("Expected responses response format context")
  }
}

///|
test "GenerationParams alternate branches preserve arrays, booleans, and empty config" {
  let openai = GenerationParams::from_openai({ "stop": ["END"], "stream": true })
  match openai.stop {
    Array(values) => assert_eq(values.length(), 1)
    _ => fail("Expected OpenAI stop array")
  }
  match openai.stream {
    True => ()
    _ => fail("Expected OpenAI stream=true")
  }

  let anthropic = GenerationParams::from_anthropic({ "stream": false })
  match anthropic.stream {
    False => ()
    _ => fail("Expected Anthropic stream=false")
  }

  let gemini = GenerationParams::from_gemini({})
  assert_eq(gemini.max_tokens, Json::null())
  assert_eq(gemini.temperature, Json::null())
  assert_eq(gemini.top_p, Json::null())
  assert_eq(gemini.top_k, Json::null())
  assert_eq(gemini.stop, Json::null())

  let gemini_empty_config = GenerationParams::from_gemini({
    "generationConfig": {},
  })
  assert_eq(gemini_empty_config.max_tokens, Json::null())
  assert_eq(gemini_empty_config.temperature, Json::null())
  assert_eq(gemini_empty_config.top_p, Json::null())
  assert_eq(gemini_empty_config.top_k, Json::null())
  assert_eq(gemini_empty_config.stop, Json::null())
  assert_eq(gemini_empty_config.response_format, None)
}

///|
test "GenerationParams::apply_to_openai respects context field name" {
  let params : GenerationParams = {
    ..GenerationParams::empty(),
    max_tokens: Json::number(777),
    temperature: Json::number(0.3),
    top_p: Json::number(0.85),
    top_k: Json::number(11),
    stop: Json::array([Json::string("END")]),
    stream: Json::boolean(false),
    reasoning_effort: Json::string("high"),
    response_format: Some(
      ResponseFormat::JsonSchema(
        name=None,
        schema={ "type": "object" },
        description=None,
        strict=Some(true),
      ),
    ),
  }
  let obj : Map[String, Json] = {}
  params.apply_to_openai(obj, {
    max_tokens: 0,
    max_tokens_field: "max_completion_tokens",
  })
  match Json::object(obj) {
    {
      "max_completion_tokens": Number(max_tokens, ..),
      "temperature": Number(temp, ..),
      "top_p": Number(top_p, ..),
      "reasoning_effort": String(reasoning_effort),
      "stop": Array(stop),
      "response_format": {
        "type": "json_schema",
        "json_schema": {
          "name": "response",
          "schema": { "type": "object", .. },
          "strict": True,
          ..
        },
        ..
      },
      ..
    } => {
      assert_eq(max_tokens.to_int(), 777)
      assert_eq(temp, 0.3)
      assert_eq(top_p, 0.85)
      assert_eq(reasoning_effort, "high")
      assert_eq(stop.length(), 1)
    }
    _ => fail("Expected mapped OpenAI fields")
  }
  assert_false(obj.contains("top_k"))
  assert_false(obj.contains("stream"))
}

///|
test "GenerationParams::apply_to_openai normalizes strict schema on bridge paths" {
  let params : GenerationParams = {
    ..GenerationParams::empty(),
    reasoning_effort: Json::string("medium"),
    response_format: Some(
      ResponseFormat::JsonSchema(
        name=Some("answer"),
        schema={
          "type": "object",
          "properties": { "url": { "type": "string", "format": "uri" } },
        },
        description=None,
        strict=Some(true),
      ),
    ),
  }
  let obj : Map[String, Json] = {}
  params.apply_to_openai(obj, TransformContext::default())
  match Json::object(obj) {
    {
      "response_format": {
        "json_schema": {
          "schema": {
            "properties": { "url": { "type": String("string"), .. }, .. },
            "additionalProperties": False,
            "required": ["url"],
            ..
          },
          ..
        },
        ..
      },
      ..
    } => ()
    _ => fail("Expected normalized OpenAI response_format")
  }
}

///|
test "GenerationParams::apply_to_responses normalizes strict schema on bridge paths" {
  let params : GenerationParams = {
    ..GenerationParams::empty(),
    reasoning_effort: Json::string("medium"),
    response_format: Some(
      ResponseFormat::JsonSchema(
        name=Some("answer"),
        schema={
          "type": "object",
          "properties": { "url": { "type": "string", "format": "uri" } },
        },
        description=Some("Structured"),
        strict=Some(true),
      ),
    ),
  }
  let obj : Map[String, Json] = {}
  params.apply_to_responses(obj)
  match Json::object(obj) {
    {
      "text": {
        "format": {
          "type": "json_schema",
          "name": "answer",
          "description": "Structured",
          "schema": {
            "properties": { "url": { "type": String("string"), .. }, .. },
            "additionalProperties": False,
            "required": ["url"],
            ..
          },
          "strict": True,
          ..
        },
        ..
      },
      "reasoning": { "effort": "medium", .. },
      ..
    } => ()
    _ => fail("Expected normalized Responses text.format")
  }
}

///|
test "GenerationParams::apply_to_openai preserves stream when true" {
  let params : GenerationParams = {
    ..GenerationParams::empty(),
    stream: Json::boolean(true),
    response_format: None,
  }
  let obj : Map[String, Json] = {}
  params.apply_to_openai(obj, TransformContext::default())
  match Json::object(obj) {
    { "stream": True, .. } => ()
    _ => fail("Expected stream=true")
  }
}

///|
test "GenerationParams::apply_to_anthropic and apply_to_gemini map fields" {
  let params : GenerationParams = {
    ..GenerationParams::empty(),
    temperature: Json::number(0.4),
    top_p: Json::number(0.92),
    top_k: Json::number(8),
    stop: Json::array([Json::string("END")]),
    stream: Json::boolean(true),
    response_format: Some(ResponseFormat::JsonObject),
  }
  let anthropic_obj : Map[String, Json] = {}
  params.apply_to_anthropic(anthropic_obj, {
    max_tokens: 2048,
    max_tokens_field: "max_tokens",
  })
  match Json::object(anthropic_obj) {
    {
      "max_tokens": Number(max_tokens, ..),
      "temperature": Number(temp, ..),
      "top_p": Number(top_p, ..),
      "top_k": Number(top_k, ..),
      "stop_sequences": Array(stop),
      "stream": True,
      "output_config": {
        "format": {
          "type": "json_schema",
          "schema": { "type": "object", .. },
          ..
        },
        ..
      },
      ..
    } => {
      assert_eq(max_tokens.to_int(), 2048)
      assert_eq(temp, 0.4)
      assert_eq(top_p, 0.92)
      assert_eq(top_k.to_int(), 8)
      assert_eq(stop.length(), 1)
    }
    _ => fail("Expected mapped Anthropic fields")
  }

  let responses_obj : Map[String, Json] = {}
  params.apply_to_responses(responses_obj)
  match Json::object(responses_obj) {
    {
      "temperature": Number(temp, ..),
      "top_p": Number(top_p, ..),
      "stream": True,
      "text": { "format": { "type": "json_object", .. }, .. },
      ..
    } => {
      assert_eq(temp, 0.4)
      assert_eq(top_p, 0.92)
    }
    _ => fail("Expected responses text format mapping")
  }

  let gemini_obj : Map[String, Json] = {}
  params.apply_to_gemini(gemini_obj, {
    max_tokens: 0,
    max_tokens_field: "max_tokens",
  })
  match Json::object(gemini_obj) {
    {
      "generationConfig": {
        "temperature": Number(temp, ..),
        "topP": Number(top_p, ..),
        "topK": Number(top_k, ..),
        "stopSequences": Array(stop),
        "responseMimeType": "application/json",
        ..
      },
      ..
    } => {
      assert_eq(temp, 0.4)
      assert_eq(top_p, 0.92)
      assert_eq(top_k.to_int(), 8)
      assert_eq(stop.length(), 1)
    }
    _ => fail("Expected generationConfig")
  }
}

///|
test "GenerationParams::apply_to_anthropic preserves raw Anthropic format carrier" {
  let params = GenerationParams::from_anthropic({
    "output_config": {
      "format": {
        "type": "json_schema",
        "schema": {
          "type": "object",
          "properties": { "url": { "type": "string", "format": "uri" } },
        },
      },
    },
  })
  let obj : Map[String, Json] = {}
  params.apply_to_anthropic(obj, {
    max_tokens: 128,
    max_tokens_field: "max_tokens",
  })
  match Json::object(obj) {
    {
      "max_tokens": Number(max_tokens, ..),
      "output_config": {
        "format": {
          "type": "json_schema",
          "schema": {
            "additionalProperties": False,
            "properties": {
              "url": { "type": String("string"), "format": "uri", .. },
              ..
            },
            ..
          },
          ..
        },
        ..
      },
      ..
    } => assert_eq(max_tokens.to_int(), 128)
    _ => fail("Expected preserved Anthropic format carrier")
  }
}

///|
test "GenerationParams keeps Gemini schema carrier distinctions" {
  let params = GenerationParams::from_gemini({
    "generationConfig": {
      "responseMimeType": "application/json",
      "responseSchema": { "type": "object", "properties": {} },
    },
  })
  let obj : Map[String, Json] = {}
  params.apply_to_gemini(obj, TransformContext::default())
  match Json::object(obj) {
    {
      "generationConfig": {
        "responseMimeType": "application/json",
        "responseSchema": { "type": "object", .. },
        ..
      },
      ..
    } => ()
    _ => fail("Expected preserved Gemini responseSchema carrier")
  }
}

///|
test "GenerationParams response_format parsing covers text, fallbacks, and malformed cases" {
  let openai_text = GenerationParams::from_openai({
    "response_format": { "type": "text" },
  })
  assert_eq(openai_text.response_format, Some(ResponseFormat::Text))
  match openai_text.response_format_context {
    Some(ctx) => {
      assert_eq(ctx.surface, "openai_chat")
      assert_eq(ctx.raw, { "type": "text" })
    }
    None => fail("Expected OpenAI text response_format context")
  }

  let openai_malformed = GenerationParams::from_openai({
    "response_format": { "type": "json_schema", "json_schema": { "name": "x" } },
  })
  assert_eq(openai_malformed.response_format, None)
  match openai_malformed.response_format_context {
    None => ()
    Some(_) => fail("Expected no malformed OpenAI response_format context")
  }

  let openai_scalar = GenerationParams::from_openai(
    Json::string("not an object"),
  )
  assert_eq(openai_scalar.response_format, None)

  let openai_scalar_format = GenerationParams::from_openai({
    "response_format": Json::string("oops"),
  })
  assert_eq(openai_scalar_format.response_format, None)

  let openai_missing_schema = GenerationParams::from_openai({
    "response_format": { "type": "json_schema" },
  })
  assert_eq(openai_missing_schema.response_format, None)

  let openai_scalar_schema_config = GenerationParams::from_openai({
    "response_format": { "type": "json_schema", "json_schema": "oops" },
  })
  assert_eq(openai_scalar_schema_config.response_format, None)

  let openai_non_bool_strict = GenerationParams::from_openai({
    "response_format": {
      "type": "json_schema",
      "json_schema": {
        "name": "answer",
        "schema": { "type": "object" },
        "strict": "false",
      },
    },
  })
  assert_eq(
    openai_non_bool_strict.response_format,
    Some(
      ResponseFormat::JsonSchema(
        name=Some("answer"),
        schema={ "type": "object" },
        description=None,
        strict=None,
      ),
    ),
  )

  let openai_unknown = GenerationParams::from_openai({
    "response_format": { "type": "yaml_object" },
  })
  assert_eq(openai_unknown.response_format, None)

  let responses_text = GenerationParams::from_responses({
    "stream": false,
    "text": { "format": { "type": "text" } },
  })
  assert_eq(responses_text.response_format, Some(ResponseFormat::Text))
  match responses_text.stream {
    False => ()
    _ => fail("Expected Responses stream=false")
  }
  match responses_text.response_format_context {
    Some(ctx) => {
      assert_eq(ctx.surface, "openai_responses")
      assert_eq(ctx.raw, { "type": "text" })
    }
    None => fail("Expected Responses text response_format context")
  }

  let responses_scalar_format = GenerationParams::from_responses({
    "text": { "format": Json::string("oops") },
  })
  assert_eq(responses_scalar_format.response_format, None)

  let responses_unknown = GenerationParams::from_responses({
    "text": { "format": { "type": "yaml_object" } },
  })
  assert_eq(responses_unknown.response_format, None)
  match responses_unknown.response_format_context {
    None => ()
    Some(_) => fail("Expected no unknown Responses response_format context")
  }

  let anthropic_malformed = GenerationParams::from_anthropic({
    "output_config": { "format": { "type": "json_schema" } },
  })
  assert_eq(anthropic_malformed.response_format, None)
  match anthropic_malformed.response_format_context {
    None => ()
    Some(_) => fail("Expected no malformed Anthropic response_format context")
  }

  let gemini_text = GenerationParams::from_gemini({
    "generationConfig": { "responseMimeType": "text/plain" },
  })
  assert_eq(gemini_text.response_format, Some(ResponseFormat::Text))
  match gemini_text.response_format_context {
    Some(ctx) => {
      assert_eq(ctx.surface, "gemini")
      assert_eq(ctx.raw, { "responseMimeType": "text/plain" })
    }
    None => fail("Expected Gemini text response_format context")
  }

  let gemini_schema_only = GenerationParams::from_gemini({
    "generationConfig": { "responseSchema": { "type": "object" } },
  })
  assert_eq(
    gemini_schema_only.response_format,
    Some(
      ResponseFormat::JsonSchema(
        name=None,
        schema={ "type": "object" },
        description=None,
        strict=None,
      ),
    ),
  )

  let gemini_json_object = GenerationParams::from_gemini({
    "generationConfig": { "responseMimeType": "application/json" },
  })
  assert_eq(
    gemini_json_object.response_format,
    Some(ResponseFormat::JsonObject),
  )
}

///|
test "GenerationParams response_format application covers raw contexts and text fallbacks" {
  let raw_openai = GenerationParams::from_openai({
    "response_format": {
      "type": "json_schema",
      "json_schema": {
        "name": "answer",
        "schema": {
          "type": "object",
          "properties": { "url": { "type": "string", "format": "uri" } },
        },
        "strict": true,
      },
    },
  })

  let openai_obj : Map[String, Json] = {}
  raw_openai.apply_to_openai(openai_obj, TransformContext::default())
  match Json::object(openai_obj) {
    {
      "response_format": {
        "json_schema": {
          "schema": {
            "properties": { "url": { "type": String("string"), .. }, .. },
            "additionalProperties": False,
            "required": ["url"],
            ..
          },
          ..
        },
        ..
      },
      ..
    } => ()
    _ => fail("Expected normalized OpenAI raw context")
  }

  let responses_obj : Map[String, Json] = {}
  raw_openai.apply_to_responses(responses_obj)
  match Json::object(responses_obj) {
    {
      "text": {
        "format": {
          "schema": {
            "properties": { "url": { "type": String("string"), .. }, .. },
            "additionalProperties": False,
            "required": ["url"],
            ..
          },
          ..
        },
        ..
      },
      ..
    } => ()
    _ => fail("Expected normalized Responses raw context")
  }

  let raw_openai_json_object = GenerationParams::from_openai({
    "response_format": { "type": "json_object" },
  })
  let raw_openai_json_object_obj : Map[String, Json] = {}
  raw_openai_json_object.apply_to_openai(
    raw_openai_json_object_obj,
    TransformContext::default(),
  )
  match Json::object(raw_openai_json_object_obj) {
    { "response_format": { "type": "json_object", .. }, .. } => ()
    _ => fail("Expected passthrough OpenAI json_object response_format")
  }

  let raw_responses_json_schema = GenerationParams::from_responses({
    "max_output_tokens": 77,
    "text": {
      "format": {
        "type": "json_schema",
        "name": "answer",
        "schema": {
          "type": "object",
          "properties": { "url": { "type": "string", "format": "uri" } },
        },
        "strict": false,
      },
    },
  })
  let raw_responses_json_schema_obj : Map[String, Json] = {}
  raw_responses_json_schema.apply_to_responses(raw_responses_json_schema_obj)
  match Json::object(raw_responses_json_schema_obj) {
    {
      "max_output_tokens": Number(max_output_tokens, ..),
      "text": {
        "format": {
          "type": "json_schema",
          "schema": {
            "properties": {
              "url": { "type": String("string"), "format": "uri", .. },
              ..
            },
            ..
          },
          "strict": False,
          ..
        },
        ..
      },
      ..
    } => assert_eq(max_output_tokens.to_int(), 77)
    _ => fail("Expected raw Responses json_schema response_format")
  }

  let anthropic_text : GenerationParams = {
    ..GenerationParams::empty(),
    response_format: Some(ResponseFormat::Text),
  }
  let anthropic_obj : Map[String, Json] = {}
  anthropic_text.apply_to_anthropic(anthropic_obj, {
    max_tokens: 64,
    max_tokens_field: "max_tokens",
  })
  match Json::object(anthropic_obj) {
    { "max_tokens": Number(max_tokens, ..), .. } =>
      assert_eq(max_tokens.to_int(), 64)
    _ => fail("Expected Anthropic max_tokens fallback")
  }
  assert_false(anthropic_obj.contains("output_config"))

  let gemini_text : GenerationParams = {
    ..GenerationParams::empty(),
    response_format: Some(ResponseFormat::Text),
  }
  let gemini_obj : Map[String, Json] = {}
  gemini_text.apply_to_gemini(gemini_obj, TransformContext::default())
  match Json::object(gemini_obj) {
    { "generationConfig": { "responseMimeType": "text/plain", .. }, .. } => ()
    _ => fail("Expected Gemini text/plain response format")
  }

  let openai_text : GenerationParams = {
    ..GenerationParams::empty(),
    response_format: Some(ResponseFormat::Text),
  }
  let openai_text_obj : Map[String, Json] = {}
  openai_text.apply_to_openai(openai_text_obj, TransformContext::default())
  match Json::object(openai_text_obj) {
    { "response_format": { "type": "text", .. }, .. } => ()
    _ => fail("Expected OpenAI text response_format")
  }

  let responses_text : GenerationParams = {
    ..GenerationParams::empty(),
    response_format: Some(ResponseFormat::Text),
  }
  let responses_text_obj : Map[String, Json] = {}
  responses_text.apply_to_responses(responses_text_obj)
  match Json::object(responses_text_obj) {
    { "text": { "format": { "type": "text", .. }, .. }, .. } => ()
    _ => fail("Expected Responses text response_format")
  }

  let raw_responses_text = GenerationParams::from_responses({
    "text": { "format": { "type": "text" } },
  })
  let raw_responses_text_obj : Map[String, Json] = {}
  raw_responses_text.apply_to_responses(raw_responses_text_obj)
  match Json::object(raw_responses_text_obj) {
    { "text": { "format": { "type": "text", .. }, .. }, .. } => ()
    _ => fail("Expected passthrough Responses text response_format")
  }

  let responses_schema_without_strict : GenerationParams = {
    ..GenerationParams::empty(),
    response_format: Some(
      ResponseFormat::JsonSchema(
        name=Some("answer"),
        schema={ "type": "object" },
        description=None,
        strict=None,
      ),
    ),
  }
  let responses_schema_without_strict_obj : Map[String, Json] = {}
  responses_schema_without_strict.apply_to_responses(
    responses_schema_without_strict_obj,
  )
  match Json::object(responses_schema_without_strict_obj) {
    {
      "text": {
        "format": {
          "type": "json_schema",
          "name": "answer",
          "schema": { "type": "object", .. },
          ..
        },
        ..
      },
      ..
    } => ()
    _ => fail("Expected Responses json_schema without strict flag")
  }
}
