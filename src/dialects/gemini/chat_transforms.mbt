///|
/// Chat Completions request/response transformations: Gemini <-> OpenAI
///
/// Transforms requests and responses between OpenAI Chat Completions
/// and Gemini GenerateContent formats, plus error format conversions.

///|
/// Transform Gemini GenerateContent request to OpenAI Chat Completions format
pub fn request_to_chat(
  body : String,
  model : String,
  ctx : @types.TransformContext,
) -> String {
  let json = @json.parse(body) catch {
    _ => abort("Gemini request transform requires valid JSON: " + body)
  }
  let result : Map[String, Json] = {}
  result["model"] = Json::string(model)
  // Convert contents to messages
  let messages : Array[Json] = []
  match json {
    { "contents": Array(contents), .. } =>
      for content in contents {
        match content {
          { "role": String(role), "parts": Array(parts), .. } => {
            let openai_role = if role == "model" { "assistant" } else { "user" }
            let texts : Array[String] = []
            for part in parts {
              match part {
                { "text": String(text), .. } => texts.push(text)
                _ => ()
              }
            }
            let content_text = texts
              .iter()
              .fold(init="", fn(acc, t) {
                if acc == "" {
                  t
                } else {
                  acc + "\n" + t
                }
              })
            let msg : Map[String, Json] = {}
            msg["role"] = Json::string(openai_role)
            msg["content"] = Json::string(content_text)
            messages.push(Json::object(msg))
          }
          _ => ()
        }
      }
    _ => ()
  }
  result["messages"] = Json::array(messages)
  // Extract and apply all generation parameters
  @types.GenerationParams::from_gemini(json).apply_to_openai(result, ctx)
  Json::object(result).stringify()
}

///|
/// Transform OpenAI Chat Completions request to Gemini GenerateContent format
pub fn chat_request_to_gemini(
  body : String,
  ctx : @types.TransformContext,
) -> String {
  let json = @json.parse(body) catch {
    _ =>
      abort(
        "Gemini chat request transform requires valid OpenAI Chat JSON: " + body,
      )
  }
  // Transform messages to Gemini contents format
  let contents : Array[Json] = []
  let system_text = StringBuilder::new()
  match json {
    { "messages": Array(msgs), .. } =>
      for msg in msgs {
        match msg {
          // Gemini uses top-level systemInstruction instead of a contents entry.
          { "role": String("system"), "content": String(content), .. } => {
            if system_text.to_string().length() > 0 {
              system_text.write_char('\n')
            }
            system_text.write_string(content)
          }
          // Assistant with tool_calls → model with functionCall parts
          { "role": String("assistant"), "tool_calls": Array(tool_calls), .. } => {
            let parts : Array[Json] = []
            // Include text content if present
            match msg {
              { "content": String(c), .. } =>
                if not(c.is_empty()) {
                  let p : Map[String, Json] = {}
                  p["text"] = Json::string(c)
                  parts.push(Json::object(p))
                }
              _ => ()
            }
            for tc in tool_calls {
              match tc {
                {
                  "function": {
                    "name": String(name),
                    "arguments": String(args_str),
                    ..
                  },
                  ..
                } => {
                  let args = parse_tool_arguments_or_abort(
                    args_str, "Gemini request transform",
                  )
                  let fc : Map[String, Json] = {}
                  fc["name"] = Json::string(name)
                  fc["args"] = args
                  let p : Map[String, Json] = {}
                  p["functionCall"] = Json::object(fc)
                  parts.push(Json::object(p))
                }
                _ => ()
              }
            }
            let c : Map[String, Json] = {}
            c["role"] = Json::string("model")
            c["parts"] = Json::array(parts)
            contents.push(Json::object(c))
          }
          // Tool result → user with functionResponse part
          {
            "role": String("tool"),
            "content": String(content),
            "tool_call_id": String(_),
            ..
          } => {
            // Need to find the function name; Gemini requires it in functionResponse.
            let name = find_tool_name_for_id(msgs, msg)
            let response : Map[String, Json] = {}
            response["content"] = Json::string(content)
            let fr : Map[String, Json] = {}
            fr["name"] = Json::string(name)
            fr["response"] = Json::object(response)
            let p : Map[String, Json] = {}
            p["functionResponse"] = Json::object(fr)
            let c : Map[String, Json] = {}
            c["role"] = Json::string("user")
            c["parts"] = Json::array([Json::object(p)])
            contents.push(Json::object(c))
          }
          // Regular messages
          { "role": String(role), "content": content, .. } => {
            let gemini_role = if role == "assistant" { "model" } else { "user" }
            let parts = transform_openai_content_to_gemini(content)
            let content_obj : Map[String, Json] = {}
            content_obj["role"] = Json::string(gemini_role)
            content_obj["parts"] = Json::array(parts)
            contents.push(Json::object(content_obj))
          }
          _ => ()
        }
      }
    _ => ()
  }
  let gemini_body : Map[String, Json] = {}
  gemini_body["contents"] = Json::array(contents)
  if system_text.to_string().length() > 0 {
    gemini_body["systemInstruction"] = content_to_json({
      role: "user",
      parts: [GeminiPart::Text(system_text.to_string())],
    })
  }
  // Convert tools: OpenAI function tools → Gemini functionDeclarations
  match json {
    { "tools": Array(openai_tools), .. } => {
      let declarations : Array[Json] = []
      for tool in openai_tools {
        match tool {
          {
            "type": String("function"),
            "function": {
              "name": String(name),
              "description": String(desc),
              "parameters": params,
              ..
            },
            ..
          } => {
            let decl : Map[String, Json] = {}
            decl["name"] = Json::string(name)
            decl["description"] = Json::string(desc)
            decl["parameters"] = params
            declarations.push(Json::object(decl))
          }
          _ => ()
        }
      }
      if declarations.length() > 0 {
        let tool_obj : Map[String, Json] = {}
        tool_obj["functionDeclarations"] = Json::array(declarations)
        gemini_body["tools"] = Json::array([Json::object(tool_obj)])
      }
    }
    _ => ()
  }
  // Extract and apply all generation parameters as generationConfig
  @types.GenerationParams::from_openai(json).apply_to_gemini(gemini_body, ctx)
  Json::object(gemini_body).stringify()
}

///|
/// Find the function name for a tool result by matching tool_call_id
/// against the preceding assistant message's tool_calls array.
fn find_tool_name_for_id(msgs : Array[Json], tool_msg : Json) -> String {
  let tc_id = match tool_msg {
    { "tool_call_id": String(id), .. } => id
    _ =>
      abort(
        "Gemini tool result is missing tool_call_id: " + tool_msg.stringify(),
      )
  }
  // Search backwards through messages for an assistant with matching tool_call
  for msg in msgs {
    match msg {
      { "role": String("assistant"), "tool_calls": Array(tcs), .. } =>
        for tc in tcs {
          match tc {
            { "id": String(id), "function": { "name": String(name), .. }, .. } =>
              if id == tc_id {
                return name
              }
            _ => ()
          }
        }
      _ => ()
    }
  }
  abort(
    "Gemini tool result does not match a preceding assistant tool call: \{tc_id}",
  )
}

///|
fn parse_tool_arguments_or_abort(args_str : String, context : String) -> Json {
  @json.parse(args_str) catch {
    _ => abort(context + " requires valid JSON tool arguments: " + args_str)
  }
}

///|
/// Transform OpenAI content to Gemini parts format
fn transform_openai_content_to_gemini(content : Json) -> Array[Json] {
  match content {
    String(text) => {
      let part : Map[String, Json] = {}
      part["text"] = Json::string(text)
      [Json::object(part)]
    }
    Array(parts) => {
      let gemini_parts : Array[Json] = []
      for part in parts {
        match part {
          { "type": String("text"), "text": String(text), .. } => {
            let p : Map[String, Json] = {}
            p["text"] = Json::string(text)
            gemini_parts.push(Json::object(p))
          }
          {
            "type": String("image_url"),
            "image_url": { "url": String(url), .. },
            ..
          } =>
            match @utils.parse_data_url(url) {
              Some((mime_type, data)) => {
                let inline_data : Map[String, Json] = {}
                inline_data["mime_type"] = Json::string(mime_type)
                inline_data["data"] = Json::string(data)
                let p : Map[String, Json] = {}
                p["inline_data"] = Json::object(inline_data)
                gemini_parts.push(Json::object(p))
              }
              None =>
                abort(
                  "Gemini chat transform does not support remote image URLs; upload via Files API or inline as data URL: \{url}",
                )
            }
          _ => ()
        }
      }
      gemini_parts
    }
    _ => []
  }
}

///|
/// Transform Gemini GenerateContent response to OpenAI Chat Completions format
pub fn response_to_chat(body : String) -> String {
  let json = @json.parse(body) catch {
    _ => abort("Gemini response transform requires valid JSON: " + body)
  }
  let choices : Array[Json] = []
  let mut idx = 0
  let mut tool_call_counter = 0
  match json {
    { "candidates": Array(candidates), .. } =>
      for candidate in candidates {
        let texts : Array[String] = []
        let tool_calls : Array[Json] = []
        match candidate {
          { "content": { "parts": Array(parts), .. }, .. } =>
            for part in parts {
              match part {
                { "text": String(t), .. } => texts.push(t)
                {
                  "functionCall": { "name": String(name), "args": args, .. },
                  ..
                } => {
                  let gemini_id = @interop_util.generate_gemini_tool_call_id(
                    name, tool_call_counter,
                  )
                  let openai_id = @interop_util.gemini_to_openai_chat_call_id(
                    gemini_id,
                  )
                  tool_calls.push(
                    @openai_chat_contract.build_tool_call_json(
                      openai_id, name, args,
                    ),
                  )
                  tool_call_counter = tool_call_counter + 1
                }
                _ => ()
              }
            }
          _ => ()
        }
        let content = normalize_structured_output_fragments(texts, "\n\n")
        let annotations = @openai_chat_contract.chat_annotations_from_response_annotations(
          collect_gemini_grounding_annotations(candidate, content),
        )
        choices.push(
          @openai_chat_contract.build_chat_choice(
            idx,
            content,
            tool_calls,
            annotations~,
          ),
        )
        idx = idx + 1
      }
    _ => ()
  }
  let id = "gemini-" + idx.to_string()
  @openai_chat_contract.build_chat_response(id, "gemini", choices)
}

///|
/// Transform OpenAI Chat Completions response to Gemini GenerateContent format.
/// Handles both text and tool_calls.
pub fn chat_response_to_gemini(body : String) -> String {
  let json = @json.parse(body) catch {
    _ =>
      abort(
        "Gemini chat response transform requires valid OpenAI Chat JSON: " +
        body,
      )
  }
  let parts : Array[Json] = []
  let message_annotations : Array[@types.ResponseAnnotation] = []
  let mut saw_choice = false
  let mut saw_message = false
  let mut saw_explicit_content = false
  match json {
    { "choices": Array(choices), .. } =>
      match choices.get(0) {
        Some(choice) => {
          saw_choice = true
          match choice {
            { "message": { "annotations": Array(annotations), .. }, .. } =>
              for annotation in parse_openai_chat_annotations(annotations) {
                message_annotations.push(annotation)
              }
            _ => ()
          }
          // Text content
          match choice {
            { "message": { "content": String(c), .. }, .. } => {
              saw_message = true
              saw_explicit_content = true
              if not(c.is_empty()) {
                let p : Map[String, Json] = {}
                p["text"] = Json::string(c)
                parts.push(Json::object(p))
              }
            }
            { "message": _, .. } => saw_message = true
            _ => ()
          }
          // Tool calls → functionCall parts
          match choice {
            { "message": { "tool_calls": Array(tcs), .. }, .. } =>
              for tc in tcs {
                match tc {
                  {
                    "function": {
                      "name": String(name),
                      "arguments": String(args_str),
                      ..
                    },
                    ..
                  } => {
                    let args = parse_tool_arguments_or_abort(
                      args_str, "Gemini response transform",
                    )
                    let fc : Map[String, Json] = {}
                    fc["name"] = Json::string(name)
                    fc["args"] = args
                    let p : Map[String, Json] = {}
                    p["functionCall"] = Json::object(fc)
                    parts.push(Json::object(p))
                  }
                  _ => ()
                }
              }
            _ => ()
          }
        }
        _ => ()
      }
    _ => ()
  }
  if parts.is_empty() {
    if saw_choice && saw_message && saw_explicit_content {
      let p : Map[String, Json] = {}
      p["text"] = Json::string("")
      parts.push(Json::object(p))
    } else {
      abort(
        "Gemini response transform requires a choice with content or tool_calls: " +
        json.stringify(),
      )
    }
  }
  let content : Map[String, Json] = {}
  content["parts"] = Json::array(parts)
  content["role"] = Json::string("model")
  let candidate : Map[String, Json] = {}
  candidate["content"] = Json::object(content)
  let rendered_text = rendered_text_from_gemini_parts(parts)
  if message_annotations.length() > 0 {
    match
      response_annotations_to_grounding_metadata(
        message_annotations, rendered_text,
      ) {
      Some(metadata) => candidate["groundingMetadata"] = metadata
      None => ()
    }
  }
  candidate["finishReason"] = Json::string("STOP")
  candidate["index"] = Json::number(0.0)
  let result : Map[String, Json] = {}
  result["candidates"] = Json::array([Json::object(candidate)])
  result["usageMetadata"] = Json::object({
    "promptTokenCount": Json::number(0.0),
    "candidatesTokenCount": Json::number(0.0),
    "totalTokenCount": Json::number(0.0),
  })
  Json::object(result).stringify()
}

///|
fn parse_openai_chat_annotations(
  annotations : Array[Json],
) -> Array[@types.ResponseAnnotation] {
  let result : Array[@types.ResponseAnnotation] = []
  for annotation in annotations {
    match annotation {
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
        let title = match annotation {
          { "url_citation": { "title": String(value), .. }, .. } if value.length() >
            0 => Some(value)
          _ => None
        }
        result.push(
          @types.ResponseAnnotation::url_citation(
            url~,
            start_index=start_index.to_int(),
            end_index=end_index.to_int(),
            title~,
          ),
        )
      }
      _ =>
        abort(
          "Gemini response transform cannot parse OpenAI chat annotation: " +
          annotation.stringify(),
        )
    }
  }
  result
}

///|
fn rendered_text_from_gemini_parts(parts : Array[Json]) -> String {
  let buf = StringBuilder::new()
  for part in parts {
    match part {
      { "text": String(text), .. } => buf.write_string(text)
      _ => ()
    }
  }
  buf.to_string()
}

///|
fn normalized_openai_error_message(json : Json) -> String {
  match json {
    { "error": { "message": String(msg), .. }, .. } => msg
    { "error": error_obj, .. } => error_obj.stringify()
    _ => json.stringify()
  }
}

///|
fn openai_error_type_to_gemini_status_and_code(
  type_ : String,
) -> (String, Double) {
  match type_ {
    "invalid_request_error" => ("INVALID_ARGUMENT", 400.0)
    "authentication_error" => ("UNAUTHENTICATED", 401.0)
    "permission_error" => ("PERMISSION_DENIED", 403.0)
    "not_found_error" => ("NOT_FOUND", 404.0)
    "rate_limit_error" => ("RESOURCE_EXHAUSTED", 429.0)
    "overloaded_error" => ("UNAVAILABLE", 503.0)
    "api_error" => ("INTERNAL", 500.0)
    _ => ("UNKNOWN", 500.0)
  }
}

///|
fn gemini_status_to_openai_error_type(status : String) -> String {
  match status {
    "INVALID_ARGUMENT" => "invalid_request_error"
    "UNAUTHENTICATED" => "authentication_error"
    "PERMISSION_DENIED" => "permission_error"
    "NOT_FOUND" => "not_found_error"
    "RESOURCE_EXHAUSTED" => "rate_limit_error"
    "UNAVAILABLE" => "overloaded_error"
    "INTERNAL" => "api_error"
    _ => "api_error"
  }
}

///|
fn normalized_gemini_error_message(error_obj : Json) -> String {
  match error_obj {
    { "message": String(msg), .. } => msg
    _ => error_obj.stringify()
  }
}

///|
pub fn is_error(json : Json) -> Bool {
  match json {
    { "error": { "message": String(_), "status": String(_), .. }, .. } => true
    { "error": { "message": String(_), "code": Number(_, ..), .. }, .. } => true
    _ => false
  }
}

///|
pub fn error_to_openai(error_obj : Json) -> String {
  let failure_type = match error_obj {
    { "status": String(status), .. } =>
      gemini_status_to_openai_error_type(status)
    _ => "api_error"
  }
  let failure_code = match error_obj {
    { "code": Number(code, ..), .. } => Some(code.to_int())
    _ => None
  }
  @types.ModelFailure::new(
    type_=failure_type,
    message=normalized_gemini_error_message(error_obj),
    code=failure_code,
  )
  .to_openai_error_json()
  .stringify()
}

///|
pub fn error_to_anthropic(error_obj : Json) -> String {
  let failure_type = match error_obj {
    { "status": String(status), .. } =>
      gemini_status_to_openai_error_type(status)
    _ => "api_error"
  }
  let failure_code = match error_obj {
    { "code": Number(code, ..), .. } => Some(code.to_int())
    _ => None
  }
  @types.ModelFailure::new(
    type_=failure_type,
    message=normalized_gemini_error_message(error_obj),
    code=failure_code,
  )
  .to_anthropic_error_json()
  .stringify()
}

///|
/// Transform OpenAI error to Gemini error format
pub fn openai_error_to_gemini(body : String) -> String {
  let json = @json.parse(body) catch {
    _ =>
      return @types.ModelFailure::new(type_="api_error", message=body)
        .to_gemini_error_json()
        .stringify()
  }
  let message = normalized_openai_error_message(json)
  let (failure_type, code) = match json {
    { "error": { "type": String(type_), .. }, .. } => {
      let (_, resolved_code) = openai_error_type_to_gemini_status_and_code(
        type_,
      )
      (type_, Some(resolved_code.to_int()))
    }
    _ => ("api_error", None)
  }
  @types.ModelFailure::new(type_=failure_type, message~, code~)
  .to_gemini_error_json()
  .stringify()
}
