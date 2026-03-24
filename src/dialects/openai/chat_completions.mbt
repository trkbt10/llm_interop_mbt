///|
/// OpenAI Chat Completions API protocol

// =============================================================================
// Message Conversion
// =============================================================================

///|
/// Convert ModelMessage to JSON (OpenAI Chat Completions format)
pub fn message_to_json(message : @types.ModelMessage) -> Json {
  match message {
    @types.ModelMessage::System(content) =>
      { "role": "system", "content": content }
    @types.ModelMessage::User(content~, name~, content_parts~) =>
      match content_parts {
        Some(parts) => {
          // Multimodal: emit content as array of parts
          let content_json = content_parts_to_openai_json(parts)
          match name {
            Some(n) =>
              {
                "role": "user",
                "content": Json::array(content_json),
                "name": n,
              }
            None => { "role": "user", "content": Json::array(content_json) }
          }
        }
        None =>
          match name {
            Some(n) => { "role": "user", "content": content, "name": n }
            None => { "role": "user", "content": content }
          }
      }
    @types.ModelMessage::Assistant(content~, tool_calls~) =>
      match tool_calls {
        Some(calls) => {
          let tool_calls_json : Array[Json] = []
          for call in calls {
            tool_calls_json.push({
              "id": call.id,
              "type": "function",
              "function": {
                "name": call.name,
                "arguments": call.arguments.stringify(),
              },
            })
          }
          {
            "role": "assistant",
            "content": content,
            "tool_calls": Json::array(tool_calls_json),
          }
        }
        None => { "role": "assistant", "content": content }
      }
    @types.ModelMessage::ToolResult(tool_call_id~, content~) =>
      { "role": "tool", "tool_call_id": tool_call_id, "content": content }
  }
}

///|
/// Convert ContentPart array to OpenAI Chat Completions content array format.
/// Ref: https://platform.openai.com/docs/api-reference/chat/create — messages[].content
fn content_parts_to_openai_json(
  parts : Array[@types.ContentPart],
) -> Array[Json] {
  let result : Array[Json] = []
  for part in parts {
    match part {
      // Ref: ChatCompletionContentPartText — {"type":"text","text":"..."}
      @types.ContentPart::Text(text) =>
        result.push({ "type": "text", "text": text })
      // Ref: ChatCompletionContentPartImage — {"type":"image_url","image_url":{"url":"...","detail":"..."}}
      @types.ContentPart::ImageUrl(url~, detail~) => {
        let image_url : Map[String, Json] = { "url": Json::string(url) }
        match detail {
          Some(d) => image_url["detail"] = Json::string(d)
          None => ()
        }
        result.push({
          "type": "image_url",
          "image_url": Json::object(image_url),
        })
      }
      // Ref: ChatCompletionContentPartImage — data URL variant
      @types.ContentPart::ImageBase64(data~, media_type~) =>
        result.push({
          "type": "image_url",
          "image_url": { "url": "data:\{media_type};base64,\{data}" },
        })
      // Ref: ChatCompletionContentPartInputAudio — {"type":"input_audio","input_audio":{"data":"...","format":"wav|mp3"}}
      @types.ContentPart::Audio(data~, format~) =>
        result.push({
          "type": "input_audio",
          "input_audio": { "data": data, "format": format },
        })
      // Ref: docs/upstream/openai-chat-completions.md:194-218 and
      // docs/upstream/openai-file-inputs.md:334-367 —
      // Chat file_data uses a data URL carrier, not bare base64.
      @types.ContentPart::Document(data~, media_type~, title~) => {
        let file : Map[String, Json] = {
          "file_data": Json::string("data:\{media_type};base64,\{data}"),
        }
        match title {
          Some(name) => file["filename"] = Json::string(name)
          None => ()
        }
        result.push({ "type": "file", "file": Json::object(file) })
      }
      // Ref: docs/upstream/openai-chat-completions.md:194-218 —
      // FileContentPart accepts uploaded file_id references.
      @types.ContentPart::FileRef(file_id~, ..) =>
        result.push({ "type": "file", "file": { "file_id": file_id } })
      // Ref: docs/upstream/openai-file-inputs.md —
      // file_url is documented for Responses API, not Chat Completions.
      @types.ContentPart::FileUrl(url~) =>
        result.push({
          "type": "text",
          "text": "[Remote file URL input — not supported by Chat Completions API; use Responses API or upload via Files API] \{url}",
        })
      // Ref: docs/upstream/openai-chat-completions.md:126-218 —
      // ChatCompletionContentPart covers text, image_url, input_audio, and file;
      // there is no native video content part in the published union.
      @types.ContentPart::Video(..) =>
        result.push({
          "type": "text",
          "text": "[Video content — not supported by Chat Completions API; use Gemini or upload via Files API]",
        })
    }
  }
  result
}

///|
/// Convert message array to OpenAI Chat Completions format JSON array
pub fn messages_to_json(messages : Array[@types.ModelMessage]) -> Array[Json] {
  let result : Array[Json] = []
  for msg in messages {
    result.push(message_to_json(msg))
  }
  result
}

// =============================================================================
// Tool Conversion
// =============================================================================

///|
/// Convert ToolDefinition to JSON (OpenAI Chat Completions format)
pub fn tool_to_json(tool : @types.ToolDefinition) -> Json {
  match tool.kind {
    @types.ToolDefinitionKind::Function =>
      {
        "type": "function",
        "function": {
          "name": tool.name,
          "description": tool.description,
          "parameters": tool.parameters,
        },
      }
    @types.ToolDefinitionKind::Builtin(builtin_type~, ..) =>
      match builtin_type {
        "web_search_preview" | "web_search_preview_2025_03_11" =>
          web_search_tool_to_json()
        _ =>
          {
            "type": "function",
            "function": {
              "name": tool.name,
              "description": tool.description,
              "parameters": tool.parameters,
            },
          }
      }
    @types.ToolDefinitionKind::WebSearchPreview(..)
    | @types.ToolDefinitionKind::WebSearchPreview20250311(..) =>
      web_search_tool_to_json()
  }
}

///|
pub fn web_search_tool_to_json() -> Json {
  {
    "type": "function",
    "function": {
      "name": @types.web_search_tool_name(),
      "description": @types.web_search_tool_description(),
      "parameters": @types.web_search_tool_parameters_schema(),
    },
  }
}

///|
/// Convert tool definition array to OpenAI Chat Completions format JSON array
pub fn tools_to_json(tools : Array[@types.ToolDefinition]) -> Array[Json] {
  let result : Array[Json] = []
  for tool in tools {
    result.push(tool_to_json(tool))
  }
  result
}

// =============================================================================
// Response Format Builders (used by cross-dialect transforms)
// =============================================================================

///|
/// Build an OpenAI Chat Completions choice JSON.
/// Used by Anthropic/Gemini response_to_chat() to construct OpenAI-format output.
pub fn build_chat_choice(
  index : Int,
  text_content : String,
  tool_calls : Array[Json],
  annotations? : Array[Json] = [],
) -> Json {
  let message : Map[String, Json] = {}
  message["role"] = Json::string("assistant")
  if tool_calls.length() > 0 {
    if text_content.is_empty() {
      message["content"] = Json::null()
    } else {
      message["content"] = Json::string(text_content)
    }
    message["tool_calls"] = Json::array(tool_calls)
  } else {
    message["content"] = Json::string(text_content)
  }
  if annotations.length() > 0 {
    message["annotations"] = Json::array(annotations)
  }
  let choice : Map[String, Json] = {}
  choice["index"] = Json::number(index.to_double())
  choice["message"] = Json::object(message)
  choice["finish_reason"] = Json::string(
    if tool_calls.length() > 0 {
      "tool_calls"
    } else {
      "stop"
    },
  )
  Json::object(choice)
}

///|
pub fn chat_annotations_from_response_annotations(
  annotations : Array[@types.ResponseAnnotation],
) -> Array[Json] {
  let result : Array[Json] = []
  for annotation in annotations {
    match response_annotation_to_chat_annotation(annotation) {
      Some(item) => result.push(item)
      None => ()
    }
  }
  result
}

///|
fn response_annotation_to_chat_annotation(
  annotation : @types.ResponseAnnotation,
) -> Json? {
  match annotation {
    @types.ResponseAnnotation::UrlCitation(
      title~,
      url~,
      start_index~,
      end_index~
    ) =>
      Some({
        "type": "url_citation",
        "url_citation": {
          "title": match title {
            Some(value) => value
            None => ""
          },
          "url": url,
          "start_index": start_index,
          "end_index": end_index,
        },
      })
    @types.ResponseAnnotation::WebSearchResultCitation(
      title~,
      url~,
      start_index~,
      end_index~,
      ..
    ) =>
      Some({
        "type": "url_citation",
        "url_citation": {
          "title": title,
          "url": url,
          "start_index": start_index,
          "end_index": end_index,
        },
      })
    _ => None
  }
}

///|
fn parse_chat_annotations(message : Json) -> Array[@types.ResponseAnnotation] {
  match message {
    { "annotations": Array(items), .. } => {
      let result : Array[@types.ResponseAnnotation] = []
      for item in items {
        match item {
          {
            "type": String("url_citation"),
            "url_citation": {
              "url": String(url),
              "start_index": Number(start_index, ..),
              "end_index": Number(end_index, ..),
              ..
            },
            ..
          } => {
            let title = match item {
              { "url_citation": { "title": String(value), .. }, .. } if value.length() >
                0 => Some(value)
              _ => None
            }
            result.push(
              @types.ResponseAnnotation::url_citation(
                url~,
                title~,
                start_index=start_index.to_int(),
                end_index=end_index.to_int(),
              ),
            )
          }
          { "type": String(_), .. } =>
            abort("Unsupported OpenAI chat annotation: " + item.stringify())
          _ =>
            abort(
              "OpenAI chat annotations must be url_citation objects: " +
              item.stringify(),
            )
        }
      }
      result
    }
    _ => []
  }
}

///|
/// Build a complete OpenAI Chat Completions response JSON string.
pub fn build_chat_response(
  id : String,
  model : String,
  choices : Array[Json],
) -> String {
  let result : Map[String, Json] = {}
  result["id"] = Json::string(id)
  result["object"] = Json::string("chat.completion")
  result["model"] = Json::string(model)
  result["choices"] = Json::array(choices)
  Json::object(result).stringify()
}

///|
/// Build an OpenAI tool_call JSON object.
pub fn build_tool_call_json(
  id : String,
  name : String,
  arguments : Json,
) -> Json {
  let func : Map[String, Json] = {}
  func["name"] = Json::string(name)
  func["arguments"] = Json::string(arguments.stringify())
  let tc : Map[String, Json] = {}
  tc["id"] = Json::string(id)
  tc["type"] = Json::string("function")
  tc["function"] = Json::object(func)
  Json::object(tc)
}

// =============================================================================
// Request Builder
// =============================================================================

///|
/// Build OpenAI Chat Completions request body
pub fn build_chat_body(
  model : String,
  messages : Array[@types.ModelMessage],
  tools : Array[@types.ToolDefinition],
  max_tokens? : Int? = None,
  temperature? : Double? = None,
  response_format? : @types.ResponseFormat? = None,
) -> Json {
  let msgs = messages_to_json(messages)
  let body : Map[String, Json] = {
    "model": Json::string(model),
    "messages": Json::array(msgs),
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
    response_format,
  }
  params.apply_to_openai(body, @types.TransformContext::default())
  if tools.length() > 0 {
    body["tools"] = Json::array(tools_to_json(tools))
    body["tool_choice"] = Json::string("auto")
  }
  Json::object(body)
}

// =============================================================================
// Response Parser
// =============================================================================

///|
/// Parse OpenAI Chat Completions response
pub fn parse_chat_response(json : Json) -> @types.ModelResponse {
  match json {
    { "choices": Array(choices), .. } => {
      if choices.length() == 0 {
        return @types.ModelResponse::ModelError("No choices in response")
      }
      let choice = choices[0]
      match choice {
        { "message": message, "finish_reason": String(finish_reason), .. } => {
          let annotations = parse_chat_annotations(message)
          // Check for tool calls
          if finish_reason == "tool_calls" {
            match message {
              { "tool_calls": tool_calls, .. } => {
                let calls = parse_tool_calls(tool_calls)
                if calls.length() > 0 {
                  let content = match message {
                    { "content": String(value), .. } => value
                    _ => ""
                  }
                  if content.length() > 0 || annotations.length() > 0 {
                    let parts : Array[@types.ResponseContentPart] = []
                    if content.length() > 0 {
                      parts.push(
                        @types.ResponseContentPart::OutputText(content),
                      )
                    }
                    return @types.ModelResponse::ToolCallsWithContent(
                      tool_calls=calls,
                      rich=@types.RichTextResponse::from_parts(
                        content~,
                        content_parts=parts,
                        annotations~,
                      ),
                    )
                  }
                  return @types.ModelResponse::ToolCalls(calls)
                }
                return @types.ModelResponse::ModelError(
                  "OpenAI chat response signaled tool_calls but contained no valid tool calls",
                )
              }
              _ =>
                return @types.ModelResponse::ModelError(
                  "OpenAI chat response signaled tool_calls without a tool_calls payload",
                )
            }
          }
          // Ref: ChatCompletionMessage.refusal — non-null when model refuses
          match message {
            { "refusal": String(reason), .. } if reason.length() > 0 =>
              return @types.ModelResponse::RichText(
                @types.RichTextResponse::new(
                  content="",
                  content_parts=Some([
                    @types.ResponseContentPart::Refusal(reason),
                  ]),
                ),
              )
            _ => ()
          }
          // Check for audio output
          // Ref: ChatCompletionAudio — {"id":"...","data":"base64...","transcript":"...","expires_at":N}
          match message {
            {
              "audio": {
                "data": String(audio_data),
                "transcript": String(transcript),
                ..
              },
              ..
            } => {
              let text = match message {
                { "content": String(c), .. } => c
                _ => transcript
              }
              let parts : Array[@types.ResponseContentPart] = []
              if text.length() > 0 {
                parts.push(@types.ResponseContentPart::OutputText(text))
              }
              parts.push(
                @types.ResponseContentPart::AudioOutput(
                  data=audio_data,
                  transcript~,
                ),
              )
              return @types.ModelResponse::RichText(
                @types.RichTextResponse::new(
                  content=text,
                  content_parts=Some(parts),
                ),
              )
            }
            _ => ()
          }
          // Extract text response
          match message {
            { "content": String(content), .. } =>
              if annotations.length() > 0 {
                @types.ModelResponse::RichText(
                  @types.RichTextResponse::from_parts(
                    content~,
                    content_parts=[
                      @types.ResponseContentPart::OutputText(content),
                    ],
                    annotations~,
                  ),
                )
              } else {
                @types.ModelResponse::Text(content)
              }
            { "content": Null, "tool_calls": tool_calls, .. } => {
              let calls = parse_tool_calls(tool_calls)
              if calls.length() > 0 {
                @types.ModelResponse::ToolCalls(calls)
              } else {
                @types.ModelResponse::ModelError(
                  "OpenAI chat response contained tool_calls without any valid calls",
                )
              }
            }
            _ => @types.ModelResponse::ModelError("Invalid message format")
          }
        }
        _ => @types.ModelResponse::ModelError("Invalid choice format")
      }
    }
    { "error": { "message": String(msg), .. }, .. } =>
      @types.ModelResponse::ModelError(msg)
    _ => @types.ModelResponse::ModelError("Unknown response format")
  }
}

///|
/// Parse tool calls from OpenAI response
pub fn parse_tool_calls(tool_calls : Json) -> Array[@types.ToolCallRequest] {
  let result : Array[@types.ToolCallRequest] = []
  match tool_calls {
    Array(calls) =>
      for call in calls {
        match call {
          {
            "id": String(id),
            "function": {
              "name": String(name),
              "arguments": String(args_str),
              ..
            },
            ..
          } => {
            let arguments = parse_chat_tool_call_arguments_or_abort(
              args_str, call,
            )
            result.push(@types.ToolCallRequest::new(id~, name~, arguments~))
          }
          _ =>
            abort(
              "OpenAI chat tool call must contain id, function.name, and function.arguments: " +
              call.stringify(),
            )
        }
      }
    _ =>
      abort(
        "OpenAI chat tool_calls must be an array: " + tool_calls.stringify(),
      )
  }
  result
}

///|
fn parse_chat_tool_call_arguments_or_abort(
  args_str : String,
  call : Json,
) -> Json {
  @json.parse(args_str) catch {
    _ =>
      abort(
        "OpenAI chat tool call arguments must be valid JSON: " +
        call.stringify(),
      )
  }
}
