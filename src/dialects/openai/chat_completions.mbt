///|
/// OpenAI Chat Completions API protocol

// =============================================================================
// Message Conversion
// =============================================================================

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
  let msgs = @openai_chat_contract.messages_to_json(messages)
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
    body["tools"] = Json::array(@openai_chat_contract.tools_to_json(tools))
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
        return parse_chat_response_failure("No choices in response", json)
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
                return parse_chat_response_failure(
                  "OpenAI chat response signaled tool_calls but contained no valid tool calls",
                  choice,
                )
              }
              _ =>
                return parse_chat_response_failure(
                  "OpenAI chat response signaled tool_calls without a tool_calls payload",
                  choice,
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
                parse_chat_response_failure(
                  "OpenAI chat response contained tool_calls without any valid calls",
                  message,
                )
              }
            }
            _ => parse_chat_response_failure("Invalid message format", choice)
          }
        }
        _ => parse_chat_response_failure("Invalid choice format", choice)
      }
    }
    { "error": error_obj, .. } =>
      match error_obj {
        { "message": String(msg), .. } => {
          let failure_type = match error_obj {
            { "type": String(type_), .. } => type_
            _ => "api_error"
          }
          let failure_code = match error_obj {
            { "code": Number(code, ..), .. } => Some(code.to_int())
            _ => None
          }
          @types.ModelResponse::Failure(
            failure=@types.ModelFailure::new(
              type_=failure_type,
              message=msg,
              code=failure_code,
              payload=Some(error_obj),
            ),
          )
        }
        _ =>
          @types.ModelResponse::Failure(
            failure=@types.ModelFailure::new(
              type_="api_error",
              message=error_obj.stringify(),
              payload=Some(error_obj),
            ),
          )
      }
    _ => parse_chat_response_failure("Unknown response format", json)
  }
}

///|
fn parse_chat_response_failure(
  message : String,
  payload : Json,
) -> @types.ModelResponse {
  @types.ModelResponse::Failure(
    failure=@types.ModelFailure::parse_error(message~, payload=Some(payload)),
  )
}

///|
/// Parse tool calls from OpenAI response
fn parse_tool_calls(tool_calls : Json) -> Array[@types.ToolCallRequest] {
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
