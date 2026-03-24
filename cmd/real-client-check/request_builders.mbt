fn structured_response_format() -> @types.ResponseFormat {
  @types.ResponseFormat::JsonSchema(
    name=Some("interop_check"),
    schema={
      "type": "object",
      "required": ["url"],
      "properties": {
        "url": { "type": "string", "format": "uri" },
      },
    },
    description=Some("Return a single URL object."),
    strict=Some(true),
  )
}

///|
fn json_object_response_format() -> @types.ResponseFormat {
  @types.ResponseFormat::JsonObject
}

///|
fn company_response_format() -> @types.ResponseFormat {
  @types.ResponseFormat::JsonSchema(
    name=Some("file_url_check"),
    schema={
      "type": "object",
      "required": ["company"],
      "properties": {
        "company": { "type": "string" },
      },
    },
    description=Some("Return the company name from the attached file."),
    strict=Some(true),
  )
}

///|
fn file_input_prompt() -> String {
  "Read the attached file and return exactly {\"company\":\"\{expected_company}\"}."
}

///|
fn build_single_file_message(
  part : @types.ContentPart,
) -> Array[@types.ModelMessage] {
  let prompt = file_input_prompt()
  [
    @types.ModelMessage::User(
      content=prompt,
      name=None,
      content_parts=Some([@types.ContentPart::Text(prompt), part]),
    ),
  ]
}

///|
fn build_inline_file_message(fixture : FileFixture) -> Array[@types.ModelMessage] {
  build_single_file_message(
    @types.ContentPart::Document(
      data=fixture.base64_data,
      media_type=fixture.media_type,
      title=Some(fixture.filename),
    ),
  )
}

///|
fn build_file_ref_message(
  file_id : String,
  media_type : String,
) -> Array[@types.ModelMessage] {
  build_single_file_message(
    @types.ContentPart::FileRef(file_id~, media_type=Some(media_type)),
  )
}

///|
fn structured_messages() -> Array[@types.ModelMessage] {
  [
    @types.ModelMessage::User(
      content="Return exactly this JSON object and nothing else: {\"url\":\"https://example.com/interop-check\"}",
      name=None,
      content_parts=None,
    ),
  ]
}

///|
fn file_url_messages() -> Array[@types.ModelMessage] {
  build_single_file_message(@types.ContentPart::FileUrl(url=expected_file_url))
}

///|
fn file_data_messages() -> Array[@types.ModelMessage] {
  build_inline_file_message(text_file_fixture())
}

///|
fn chat_file_data_messages() -> Array[@types.ModelMessage] {
  build_inline_file_message(pdf_file_fixture())
}

///|
fn file_id_messages(file_id : String) -> Array[@types.ModelMessage] {
  build_file_ref_message(file_id, text_file_fixture().media_type)
}

///|
fn chat_file_id_messages(file_id : String) -> Array[@types.ModelMessage] {
  build_file_ref_message(file_id, pdf_file_fixture().media_type)
}

///|
fn translation_messages() -> Array[@types.ModelMessage] {
  [
    @types.ModelMessage::System(
      "Return only the requested JSON object with no extra prose.",
    ),
    @types.ModelMessage::User(
      content="Return exactly this JSON object and nothing else: {\"url\":\"https://example.com/interop-check\"}",
      name=None,
      content_parts=None,
    ),
  ]
}

///|
fn raw_openai_surface_translation_body(
  model : String,
  response_format : @types.ResponseFormat,
) -> String {
  @openai.build_chat_body(
    model,
    translation_messages(),
    [],
    max_tokens=Some(128),
    temperature=Some(0.0),
    response_format=Some(response_format),
  ).stringify()
}

///|
fn openai_function_tool_choice(tool_name : String) -> Json {
  {
    "type": "function",
    "function": { "name": tool_name },
  }
}

///|
fn with_json_boolean_field(body : String, key : String) -> String {
  let json = @json.parse(body) catch { _ => return body }
  match json {
    Object(obj) => {
      obj[key] = Json::boolean(true)
      Json::object(obj).stringify()
    }
    _ => body
  }
}

///|
fn raw_openai_surface_tool_body(
  model : String,
  messages : Array[@types.ModelMessage],
  response_format : @types.ResponseFormat?,
  tool_choice : Json?,
) -> String {
  let body = @openai.build_chat_body(
    model,
    messages,
    [tool_definition()],
    max_tokens=Some(128),
    temperature=Some(0.0),
    response_format~,
  )
  match (body, tool_choice) {
    (Object(obj), Some(choice)) => {
      obj["tool_choice"] = choice
      Json::object(obj).stringify()
    }
    _ => body.stringify()
  }
}

///|
fn basic_messages() -> Array[@types.ModelMessage] {
  [
    @types.ModelMessage::User(
      content="Reply with exactly OK and nothing else.",
      name=None,
      content_parts=None,
    ),
  ]
}

///|
fn tool_definition() -> @types.ToolDefinition {
  @types.ToolDefinition::new(
    name="lookup_verification_url",
    description="Return the verification URL for a given label",
    parameters={
      "type": "object",
      "properties": { "label": { "type": "string" } },
      "required": ["label"],
    },
  )
}

///|
fn tool_turn_one_messages(label : String) -> Array[@types.ModelMessage] {
  [
    @types.ModelMessage::User(
      content=
        "Call the tool lookup_verification_url exactly once with {\"label\":\"\{label}\"} and no extra text. After you receive the tool result, reply with exactly that JSON object and nothing else.",
      name=None,
      content_parts=None,
    ),
  ]
}

///|
fn tool_followup_messages(
  label : String,
  extracted : ExtractedToolCall,
) -> Array[@types.ModelMessage] {
  [
    @types.ModelMessage::User(
      content=
        "Call the tool lookup_verification_url exactly once with {\"label\":\"\{label}\"} and no extra text. After you receive the tool result, reply with exactly that JSON object and nothing else.",
      name=None,
      content_parts=None,
    ),
    @types.ModelMessage::Assistant(
      content=extracted.assistant_content,
      tool_calls=Some([extracted.call]),
    ),
    @types.ModelMessage::ToolResult(
      tool_call_id=extracted.call.id,
      content="{\"url\":\"\{expected_tool_url(label)}\"}",
    ),
  ]
}

///|
fn append_tool_followup_messages(
  messages : Array[@types.ModelMessage],
  label : String,
  extracted : ExtractedToolCall,
) -> Array[@types.ModelMessage] {
  let result = messages.copy()
  result.push(
    @types.ModelMessage::Assistant(
      content=extracted.assistant_content,
      tool_calls=Some([extracted.call]),
    ),
  )
  result.push(
    @types.ModelMessage::ToolResult(
      tool_call_id=extracted.call.id,
      content="{\"url\":\"\{expected_tool_url(label)}\"}",
    ),
  )
  result
}

///|
