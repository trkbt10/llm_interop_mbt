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
      // Ref: docs/upstream/gemini-generate-content.md:52-63,650-682 —
      // request contents use user/model roles, while system instructions live in
      // the top-level systemInstruction field. This helper preserves the
      // existing fallback of downgrading system prompts into user text.
      Some({ role: "user", parts: [GeminiPart::Text(content)] })
    @types.ModelMessage::User(content~, content_parts~, ..) =>
      match content_parts {
        Some(parts) => {
          let gemini_parts : Array[GeminiPart] = []
          // Ref: https://ai.google.dev/api/generate-content — Part
          for part in parts {
            match part {
              // Ref: Part.text — {"text":"..."}
              @types.ContentPart::Text(text) =>
                gemini_parts.push(GeminiPart::Text(text))
              // Ref: docs/upstream/gemini-files-api.md:1-17,33-55 —
              // file prompting examples use uploaded file URIs via
              // createPartFromUri.
              // Ref: docs/upstream/gemini-video-understanding.md:241-280 —
              // preview YouTube URLs are a documented fileUri exception.
              // Inference: the vendored snapshot does not document generic
              // remote image URLs as Part.fileData inputs, so ImageUrl falls
              // back to a text placeholder instead of emitting an undocumented
              // request shape.
              @types.ContentPart::ImageUrl(url~, ..) =>
                gemini_parts.push(GeminiPart::Text("[Image: \{url}]"))
              // Ref: Part.inlineData — {"inlineData":{"mimeType":"image/*","data":"..."}}
              @types.ContentPart::ImageBase64(data~, media_type~) =>
                gemini_parts.push(
                  GeminiPart::InlineData(mime_type=media_type, data~),
                )
              // Ref: Part.inlineData — {"inlineData":{"mimeType":"audio/*","data":"..."}}
              // Ref: https://ai.google.dev/gemini-api/docs/audio
              @types.ContentPart::Audio(data~, format~) => {
                let mime = "audio/\{format}"
                gemini_parts.push(GeminiPart::InlineData(mime_type=mime, data~))
              }
              // Ref: Part.inlineData — {"inlineData":{"mimeType":"application/pdf","data":"..."}}
              // Ref: https://ai.google.dev/gemini-api/docs/document-processing
              @types.ContentPart::Document(data~, media_type~, ..) =>
                gemini_parts.push(
                  GeminiPart::InlineData(mime_type=media_type, data~),
                )
              // Ref: Part.fileData — {"fileData":{"fileUri":"files/...","mimeType":"..."}}
              // Ref: https://ai.google.dev/gemini-api/docs/files
              @types.ContentPart::FileRef(file_id~, media_type~) =>
                gemini_parts.push(
                  GeminiPart::FileData(file_uri=file_id, mime_type=media_type),
                )
              // Ref: docs/upstream/gemini-files-api.md —
              // generic HTTP(S) document URLs are not documented fileData URIs.
              @types.ContentPart::FileUrl(url~) =>
                gemini_parts.push(GeminiPart::Text("[File: \{url}]"))
              // Ref: Part.inlineData — {"inlineData":{"mimeType":"video/*","data":"..."}}
              // Ref: https://ai.google.dev/gemini-api/docs/video-understanding
              @types.ContentPart::Video(data~, media_type~) =>
                gemini_parts.push(
                  GeminiPart::InlineData(mime_type=media_type, data~),
                )
            }
          }
          Some({ role: "user", parts: gemini_parts })
        }
        None => Some({ role: "user", parts: [GeminiPart::Text(content)] })
      }
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
    @types.ModelMessage::ToolResult(tool_call_id~, content=_) =>
      abort(
        "Gemini ToolResult conversion requires a preceding assistant tool call to resolve the function name: " +
        tool_call_id,
      )
  }
}

///|
/// Convert message array to Gemini contents
pub fn messages_to_contents(
  messages : Array[@types.ModelMessage],
) -> Array[GeminiContent] {
  let result : Array[GeminiContent] = []
  let tool_names : Map[String, String] = {}
  for msg in messages {
    match msg {
      @types.ModelMessage::Assistant(tool_calls=Some(calls), ..) =>
        for call in calls {
          tool_names[call.id] = call.name
        }
      _ => ()
    }
    match msg {
      @types.ModelMessage::ToolResult(tool_call_id~, content~) => {
        let response : Json = @json.parse(content) catch {
          _ => Json::string(content)
        }
        let name = resolve_tool_result_name_or_abort(tool_names, tool_call_id)
        result.push({
          role: "user",
          parts: [GeminiPart::FunctionResponse(name~, response~)],
        })
      }
      _ =>
        match message_to_content(msg) {
          Some(content) => result.push(content)
          None => ()
        }
    }
  }
  result
}

///|
fn resolve_tool_result_name_or_abort(
  tool_names : Map[String, String],
  tool_call_id : String,
) -> String {
  match tool_names.get(tool_call_id) {
    Some(name) => name
    None =>
      abort(
        "Gemini tool result does not match any preceding assistant tool call: " +
        tool_call_id,
      )
  }
}

///|
fn extract_system_instruction(
  messages : Array[@types.ModelMessage],
) -> GeminiContent? {
  let text = StringBuilder::new()
  for msg in messages {
    match msg {
      @types.ModelMessage::System(content) => {
        if text.to_string().length() > 0 {
          text.write_char('\n')
        }
        text.write_string(content)
      }
      _ => ()
    }
  }
  if text.to_string().length() > 0 {
    Some({ role: "user", parts: [GeminiPart::Text(text.to_string())] })
  } else {
    None
  }
}

///|
fn non_system_messages(
  messages : Array[@types.ModelMessage],
) -> Array[@types.ModelMessage] {
  let result : Array[@types.ModelMessage] = []
  for msg in messages {
    match msg {
      @types.ModelMessage::System(_) => ()
      _ => result.push(msg)
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
    @types.ToolDefinitionKind::Builtin(builtin_type~, config~) =>
      build_builtin_tool_json(builtin_type, config)
    @types.ToolDefinitionKind::WebSearchPreview(..)
    | @types.ToolDefinitionKind::WebSearchPreview20250311(..) =>
      web_search_tool_to_json()
  }
}

///|
fn build_builtin_tool_json(type_ : String, config : Json) -> Json {
  if is_native_gemini_tool_type(type_) {
    let result : Map[String, Json] = {}
    result[type_] = native_gemini_tool_config_or_abort(type_, config)
    Json::object(result)
  } else {
    ensure_bridged_builtin_config_is_empty_or_abort(type_, config)
    {
      "name": tool_name_from_builtin(type_),
      "description": "",
      "parameters": Json::object({}),
    }
  }
}

///|
fn native_gemini_tool_config_or_abort(type_ : String, config : Json) -> Json {
  match config {
    Object(fields) => Json::object(fields)
    Null => Json::object({})
    _ =>
      abort(
        "Gemini native builtin tool config must be an object for \{type_}: " +
        config.stringify(),
      )
  }
}

///|
fn ensure_bridged_builtin_config_is_empty_or_abort(
  type_ : String,
  config : Json,
) -> Unit {
  match config {
    Object(fields) if fields.is_empty() => ()
    Null => ()
    Object(_) =>
      abort(
        "Gemini builtin bridge cannot preserve provider-specific config for \{type_}: " +
        config.stringify(),
      )
    _ =>
      abort(
        "Gemini builtin bridge requires an object config for \{type_}: " +
        config.stringify(),
      )
  }
}

///|
fn tool_name_from_builtin(type_ : String) -> String {
  match type_ {
    "web_search_preview" | "web_search_preview_2025_03_11" =>
      @types.web_search_tool_name()
    _ => type_
  }
}

///|
fn is_native_gemini_tool_type(type_ : String) -> Bool {
  [
    "googleSearchRetrieval", "codeExecution", "googleSearch", "computerUse", "urlContext",
    "fileSearch", "googleMaps",
  ].contains(type_)
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
  let function_declarations : Array[Json] = []
  let native_tools : Map[String, Json] = {}
  for tool in tools {
    match tool.kind {
      @types.ToolDefinitionKind::Builtin(builtin_type~, ..) => {
        let json = tool_to_json(tool)
        if is_native_gemini_tool_type(builtin_type) {
          match json {
            Object(fields) =>
              match fields.get(builtin_type) {
                Some(value) => native_tools[builtin_type] = value
                None =>
                  abort(
                    "Gemini native builtin tool JSON is missing expected key \{builtin_type}: " +
                    json.stringify(),
                  )
              }
            _ =>
              abort(
                "Gemini native builtin tool JSON must be an object: " +
                json.stringify(),
              )
          }
        } else {
          function_declarations.push(json)
        }
      }
      _ => function_declarations.push(tool_to_json(tool))
    }
  }
  let result : Map[String, Json] = native_tools
  if function_declarations.length() > 0 {
    result["functionDeclarations"] = Json::array(function_declarations)
  }
  Json::object(result)
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
  response_format? : @types.ResponseFormat? = None,
) -> Json {
  let contents = messages_to_contents(non_system_messages(messages))
  let contents_json = contents.map(content_to_json)
  let body : Map[String, Json] = { "contents": Json::array(contents_json) }
  match extract_system_instruction(messages) {
    Some(content) => body["systemInstruction"] = content_to_json(content)
    None => ()
  }
  let params : @types.GenerationParams = {
    ..@types.GenerationParams::empty(),
    max_tokens: match max_tokens {
      Some(max) => Json::number(max.to_double())
      None => Json::null()
    },
    temperature: match temperature {
      Some(temp) => Json::number(temp)
      None => Json::null()
    },
    top_p: match top_p {
      Some(value) => Json::number(value)
      None => Json::null()
    },
    top_k: match top_k {
      Some(value) => Json::number(value.to_double())
      None => Json::null()
    },
    response_format,
  }
  params.apply_to_gemini(body, @types.TransformContext::default())
  if tools.length() > 0 {
    body["tools"] = Json::array([tools_to_json(tools)])
  }
  Json::object(body)
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
          // Extract text and structured content parts
          let text = extract_gemini_text(parts)
          let annotations = collect_gemini_grounding_annotations(
            candidate, text,
          )
          let response_parts = extract_gemini_content_parts(parts)
          if tool_calls.length() > 0 {
            match response_parts {
              Some(rparts) =>
                @types.ModelResponse::ToolCallsWithContent(
                  tool_calls~,
                  rich=@types.RichTextResponse::from_parts(
                    content=text,
                    content_parts=rparts,
                    annotations~,
                  ),
                )
              None =>
                if text.length() > 0 || annotations.length() > 0 {
                  let parts : Array[@types.ResponseContentPart] = []
                  if text.length() > 0 {
                    parts.push(@types.ResponseContentPart::OutputText(text))
                  }
                  @types.ModelResponse::ToolCallsWithContent(
                    tool_calls~,
                    rich=@types.RichTextResponse::from_parts(
                      content=text,
                      content_parts=parts,
                      annotations~,
                    ),
                  )
                } else {
                  @types.ModelResponse::ToolCalls(tool_calls)
                }
            }
          } else {
            match response_parts {
              Some(rparts) =>
                @types.ModelResponse::RichText(
                  @types.RichTextResponse::from_parts(
                    content=text,
                    content_parts=rparts,
                    annotations~,
                  ),
                )
              None =>
                if annotations.length() > 0 {
                  @types.ModelResponse::RichText(
                    @types.RichTextResponse::from_parts(
                      content=text,
                      content_parts=[
                        @types.ResponseContentPart::OutputText(text),
                      ],
                      annotations~,
                    ),
                  )
                } else {
                  @types.ModelResponse::Text(text)
                }
            }
          }
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
        if name == @types.web_search_tool_name() {
          let query = match args {
            { "query": String(value), .. } => Some(value)
            _ => None
          }
          let queries = match args {
            { "queries": Array(values), .. } => {
              let result_queries : Array[String] = []
              for value in values {
                match value {
                  String(text) => result_queries.push(text)
                  _ => ()
                }
              }
              Some(result_queries)
            }
            _ => None
          }
          result.push(@types.ToolCallRequest::web_search(id~, query~, queries~))
        } else {
          result.push(@types.ToolCallRequest::new(id~, name~, arguments=args))
        }
        index = index + 1
      }
      { "functionCall": _, .. } =>
        abort(
          "Gemini functionCall part is missing required name/args fields: " +
          part.stringify(),
        )
      _ => ()
    }
  }
  result
}

///|
/// Extract text from Gemini response parts
fn extract_gemini_text(parts : Array[Json]) -> String {
  let fragments : Array[String] = []
  for part in parts {
    match part {
      { "text": String(_), "thought": True, .. } => ()
      { "text": String(t), .. } => fragments.push(t)
      _ => ()
    }
  }
  normalize_structured_output_fragments(fragments, "\n")
}

///|
/// Extract structured content parts from Gemini response parts
/// Returns None if response is text-only, Some(parts) if code execution etc. present
fn extract_gemini_content_parts(
  parts : Array[Json],
) -> Array[@types.ResponseContentPart]? {
  let result : Array[@types.ResponseContentPart] = []
  let mut has_non_text = false
  for part in parts {
    let thought_signature = match part {
      { "thoughtSignature": String(value), .. } => Some(value)
      _ => None
    }
    match part {
      { "text": String(t), "thought": True, .. } => {
        result.push(@types.ResponseContentPart::Thinking(text=t))
        has_non_text = true
      }
      { "text": String(t), .. } =>
        result.push(@types.ResponseContentPart::OutputText(t))
      {
        "executableCode": {
          "language": String(language),
          "code": String(code),
          ..
        },
        ..
      } => {
        result.push(@types.ResponseContentPart::CodeExecution(language~, code~))
        has_non_text = true
      }
      {
        "codeExecutionResult": {
          "outcome": String(outcome),
          "output": String(output),
          ..
        },
        ..
      } => {
        result.push(@types.ResponseContentPart::CodeResult(outcome~, output~))
        has_non_text = true
      }
      _ => ()
    }
    match thought_signature {
      Some(value) => {
        result.push(@types.ResponseContentPart::RedactedThinking(data=value))
        has_non_text = true
      }
      None => ()
    }
  }
  if has_non_text {
    Some(result)
  } else {
    None
  }
}

// =============================================================================
// Streaming Support
// =============================================================================

///|
/// Parse Gemini streaming chunk
/// Parse a Gemini streaming chunk into text and tool calls.
/// Extracts text from Part.text, Part.executableCode, and Part.codeExecutionResult.
/// Ref: docs/upstream/gemini-generate-content.md:52-57,3433-3434 —
/// the GenerateContent schema documents text/function tools plus thinking/code
/// execution features at the API level.
/// Inference: this vendored snapshot does not spell out Part.executableCode or
/// Part.codeExecutionResult in the Part schema, so we keep parsing the runtime
/// shapes seen in streaming responses:
///   executableCode: {"language":"PYTHON","code":"..."}
///   codeExecutionResult: {"outcome":"OUTCOME_OK","output":"..."}
pub fn parse_stream_chunk(
  chunk_json : Json,
) -> (String, Array[@types.ToolCallRequest])? {
  match chunk_json {
    { "candidates": Array(candidates), .. } =>
      if candidates.length() > 0 {
        parse_first_gemini_stream_candidate(candidates[0])
      } else if is_documented_gemini_stream_metadata_only_chunk(chunk_json) {
        None
      } else {
        abort(
          "Gemini stream chunk returned no candidates without documented metadata: " +
          chunk_json.stringify(),
        )
      }
    _ =>
      if is_documented_gemini_stream_metadata_only_chunk(chunk_json) {
        None
      } else {
        abort(
          "Unsupported Gemini stream chunk format: " + chunk_json.stringify(),
        )
      }
  }
}

///|
fn parse_first_gemini_stream_candidate(
  candidate : Json,
) -> (String, Array[@types.ToolCallRequest])? {
  match candidate {
    { "content": { "parts": Array(parts), .. }, .. } => {
      let text_buf = StringBuilder::new()
      // Ref: Part.text
      for part in parts {
        match part {
          { "text": String(t), .. } => text_buf.write_string(t)
          // Inference: docs/upstream/gemini-generate-content.md:52-57,3433-3434
          // documents code execution support, but not this concrete Part key.
          // Structure: {"executableCode":{"language":"PYTHON","code":"..."}}
          {
            "executableCode": {
              "language": String(lang),
              "code": String(code),
              ..
            },
            ..
          } => {
            text_buf.write_string("```")
            text_buf.write_string(lang.to_lower())
            text_buf.write_char('\n')
            text_buf.write_string(code)
            text_buf.write_string("\n```\n")
          }
          // Inference: docs/upstream/gemini-generate-content.md:52-57,3433-3434
          // documents code execution support, but not this concrete Part key.
          // Structure: {"codeExecutionResult":{"outcome":"OUTCOME_OK","output":"..."}}
          {
            "codeExecutionResult": {
              "outcome": String(outcome),
              "output": String(output),
              ..
            },
            ..
          } => {
            text_buf.write_string("Execution [")
            text_buf.write_string(outcome)
            text_buf.write_string("]: ")
            text_buf.write_string(output)
          }
          _ => ()
        }
      }
      let tool_calls = parse_function_calls(parts)
      Some((text_buf.to_string(), tool_calls))
    }
    // Ref: docs/upstream/gemini-generate-content.md:2915-2939
    // finishReason/finishMessage/safety metadata may appear when the candidate
    // has stopped or has been blocked, without content parts in that chunk.
    { "finishReason": String(_), .. } => None
    _ =>
      abort(
        "Gemini stream candidate is missing content.parts and finishReason: " +
        candidate.stringify(),
      )
  }
}

///|
fn is_documented_gemini_stream_metadata_only_chunk(chunk_json : Json) -> Bool {
  // Ref: docs/upstream/gemini-generate-content.md:2780-2790
  // Metadata-only responses may include promptFeedback/usage/model metadata.
  match chunk_json {
    Object(fields) =>
      fields.contains("promptFeedback") ||
      fields.contains("usageMetadata") ||
      fields.contains("modelVersion") ||
      fields.contains("responseId") ||
      fields.contains("modelStatus")
    _ => false
  }
}
