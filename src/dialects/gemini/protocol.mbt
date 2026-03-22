///|
/// Gemini GenerateContent API protocol

// =============================================================================
// Types
// =============================================================================

///|
/// Gemini part types
pub(all) enum GeminiPart {
  /// Text part
  Text(String)
  /// Function call part (no ID - name-based reference)
  FunctionCall(name~ : String, args~ : Json)
  /// Function response part (name-based reference)
  FunctionResponse(name~ : String, response~ : Json)
  /// Inline data (base64)
  InlineData(mime_type~ : String, data~ : String)
  /// File data
  FileData(file_uri~ : String, mime_type~ : String?)
}

///|
/// Gemini content
pub(all) struct GeminiContent {
  role : String // "user" | "model" | "function"
  parts : Array[GeminiPart]
}

// =============================================================================
// Message Conversion
// =============================================================================

///|
/// Convert ModelMessage to GeminiContent
pub fn message_to_content(message : @types.ModelMessage) -> GeminiContent? {
  match message {
    @types.ModelMessage::System(content) =>
      // Gemini treats system as user instruction
      Some({ role: "user", parts: [GeminiPart::Text(content)] })
    @types.ModelMessage::User(content~, ..) =>
      Some({ role: "user", parts: [GeminiPart::Text(content)] })
    @types.ModelMessage::Assistant(content~, tool_calls~) =>
      match tool_calls {
        Some(calls) if calls.length() > 0 => {
          let parts : Array[GeminiPart] = []
          if content.length() > 0 {
            parts.push(GeminiPart::Text(content))
          }
          for call in calls {
            parts.push(
              GeminiPart::FunctionCall(name=call.name, args=call.arguments),
            )
          }
          Some({ role: "model", parts })
        }
        _ =>
          if content.length() > 0 {
            Some({ role: "model", parts: [GeminiPart::Text(content)] })
          } else {
            None
          }
      }
    @types.ModelMessage::ToolResult(tool_call_id~, content~) => {
      // Gemini uses function name, not ID - extract name from ID if possible
      // ID format: "call_xxx" or "toolu_xxx" -> use as-is for tracking
      // In practice, caller should provide the tool name separately
      let response : Json = @json.parse(content) catch {
        _ => Json::string(content)
      }
      Some({
        role: "function",
        parts: [GeminiPart::FunctionResponse(name=tool_call_id, response~)],
      })
    }
  }
}

///|
/// Convert message array to Gemini contents
pub fn messages_to_contents(
  messages : Array[@types.ModelMessage],
) -> Array[GeminiContent] {
  let result : Array[GeminiContent] = []
  for msg in messages {
    match message_to_content(msg) {
      Some(content) => result.push(content)
      None => ()
    }
  }
  result
}

///|
/// Convert GeminiPart to JSON
fn gemini_part_to_json(part : GeminiPart) -> Json {
  match part {
    GeminiPart::Text(text) => { "text": text }
    GeminiPart::FunctionCall(name~, args~) =>
      { "functionCall": { "name": name, "args": args } }
    GeminiPart::FunctionResponse(name~, response~) =>
      { "functionResponse": { "name": name, "response": response } }
    GeminiPart::InlineData(mime_type~, data~) =>
      { "inlineData": { "mimeType": mime_type, "data": data } }
    GeminiPart::FileData(file_uri~, mime_type~) =>
      match mime_type {
        Some(mt) => { "fileData": { "fileUri": file_uri, "mimeType": mt } }
        None => { "fileData": { "fileUri": file_uri } }
      }
  }
}

///|
/// Convert GeminiContent to JSON
pub fn content_to_json(content : GeminiContent) -> Json {
  let parts = content.parts.map(gemini_part_to_json)
  { "role": content.role, "parts": Json::array(parts) }
}

// =============================================================================
// Tool Conversion
// =============================================================================

///|
/// Convert ToolDefinition to Gemini function declaration JSON
pub fn tool_to_json(tool : @types.ToolDefinition) -> Json {
  match tool.kind {
    @types.ToolDefinitionKind::Function =>
      {
        "name": tool.name,
        "description": tool.description,
        "parameters": tool.parameters,
      }
    @types.ToolDefinitionKind::WebSearchPreview(..)
    | @types.ToolDefinitionKind::WebSearchPreview20250311(..) =>
      web_search_tool_to_json()
  }
}

///|
fn web_search_tool_to_json() -> Json {
  {
    "name": @types.web_search_tool_name(),
    "description": @types.web_search_tool_description(),
    "parameters": @types.web_search_tool_parameters_schema(),
  }
}

///|
/// Convert tool definitions array to Gemini tools format
pub fn tools_to_json(tools : Array[@types.ToolDefinition]) -> Json {
  let function_declarations = tools.map(tool_to_json)
  { "functionDeclarations": Json::array(function_declarations) }
}

// =============================================================================
// Request Builder
// =============================================================================

///|
/// Build Gemini GenerateContent request body
pub fn build_body(
  messages : Array[@types.ModelMessage],
  tools : Array[@types.ToolDefinition],
  max_tokens? : Int? = None,
  temperature? : Double? = None,
  top_p? : Double? = None,
  top_k? : Int? = None,
) -> Json {
  let contents = messages_to_contents(messages)
  let contents_json = contents.map(content_to_json)
  let mut body : Json = { "contents": Json::array(contents_json) }
  // Generation config
  let mut has_gen_config = false
  let mut gen_config : Json = {}
  match max_tokens {
    Some(max) => {
      gen_config = @utils.set_json_field(
        gen_config,
        "maxOutputTokens",
        Json::number(max.to_double()),
      )
      has_gen_config = true
    }
    None => ()
  }
  match temperature {
    Some(temp) => {
      gen_config = @utils.set_json_field(
        gen_config,
        "temperature",
        Json::number(temp),
      )
      has_gen_config = true
    }
    None => ()
  }
  match top_p {
    Some(p) => {
      gen_config = @utils.set_json_field(gen_config, "topP", Json::number(p))
      has_gen_config = true
    }
    None => ()
  }
  match top_k {
    Some(k) => {
      gen_config = @utils.set_json_field(
        gen_config,
        "topK",
        Json::number(k.to_double()),
      )
      has_gen_config = true
    }
    None => ()
  }
  if has_gen_config {
    body = @utils.set_json_field(body, "generationConfig", gen_config)
  }
  // Tools
  if tools.length() > 0 {
    body = @utils.set_json_field(
      body,
      "tools",
      Json::array([tools_to_json(tools)]),
    )
  }
  body
}

// =============================================================================
// Response Parser
// =============================================================================

///|
/// Parse Gemini response
pub fn parse_response(response_json : Json) -> @types.ModelResponse {
  match response_json {
    { "candidates": Array(candidates), .. } => {
      if candidates.length() == 0 {
        return @types.ModelResponse::ModelError("No candidates in response")
      }
      let candidate = candidates[0]
      match candidate {
        { "content": { "parts": Array(parts), .. }, .. } => {
          let tool_calls = parse_function_calls(parts)
          if tool_calls.length() > 0 {
            return @types.ModelResponse::ToolCalls(tool_calls)
          }
          // Extract text
          let text = extract_gemini_text(parts)
          @types.ModelResponse::Text(text)
        }
        { "finishReason": String("SAFETY"), .. } =>
          @types.ModelResponse::ModelError("Response blocked by safety filters")
        _ => @types.ModelResponse::ModelError("Invalid candidate format")
      }
    }
    { "error": { "message": String(msg), .. }, .. } =>
      @types.ModelResponse::ModelError(msg)
    _ => @types.ModelResponse::ModelError("Unknown response format")
  }
}

///|
/// Parse function calls from Gemini response parts
pub fn parse_function_calls(
  parts : Array[Json],
) -> Array[@types.ToolCallRequest] {
  let result : Array[@types.ToolCallRequest] = []
  let mut index = 0
  for part in parts {
    match part {
      { "functionCall": { "name": String(name), "args": args, .. }, .. } => {
        // Gemini doesn't have call IDs - generate one based on index
        let id = @interop_util.generate_gemini_tool_call_id(name, index)
        result.push(@types.ToolCallRequest::new(id~, name~, arguments=args))
        index = index + 1
      }
      _ => ()
    }
  }
  result
}

///|
/// Extract text from Gemini response parts
fn extract_gemini_text(parts : Array[Json]) -> String {
  let text = StringBuilder::new()
  for part in parts {
    match part {
      { "text": String(t), .. } => {
        if text.to_string().length() > 0 {
          text.write_char('\n')
        }
        text.write_string(t)
      }
      _ => ()
    }
  }
  text.to_string()
}

// =============================================================================
// Streaming Support
// =============================================================================

///|
/// Parse Gemini streaming chunk
pub fn parse_stream_chunk(
  chunk_json : Json,
) -> (String, Array[@types.ToolCallRequest])? {
  match chunk_json {
    { "candidates": Array(candidates), .. } =>
      if candidates.length() > 0 {
        match candidates[0] {
          { "content": { "parts": Array(parts), .. }, .. } => {
            let text = extract_gemini_text(parts)
            let tool_calls = parse_function_calls(parts)
            Some((text, tool_calls))
          }
          _ => None
        }
      } else {
        None
      }
    _ => None
  }
}
