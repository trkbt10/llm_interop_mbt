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
  let json = @json.parse(body) catch { _ => return body }
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
  let json = @json.parse(body) catch { _ => return body }
  // Transform messages to Gemini contents format
  let contents : Array[Json] = []
  match json {
    { "messages": Array(msgs), .. } =>
      for msg in msgs {
        match msg {
          // Skip system messages (Gemini handles them differently)
          { "role": String("system"), .. } => ()
          // Assistant with tool_calls → model with functionCall parts
          {
            "role": String("assistant"),
            "tool_calls": Array(tool_calls),
            ..
          } => {
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
                  let args : Json = @json.parse(args_str) catch { _ => {} }
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
            // We extract it from the tool_call_id by looking at the previous assistant message.
            // Fallback: use a generic name since Gemini needs name field.
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
    _ => return "unknown"
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
  "unknown"
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
              None => ()
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
  let json = @json.parse(body) catch { _ => return body }
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
                { "functionCall": { "name": String(name), "args": args, .. }, .. } => {
                  let gemini_id = @interop_util.generate_gemini_tool_call_id(name, tool_call_counter)
                  let openai_id = @interop_util.gemini_to_openai_chat_call_id(gemini_id)
                  tool_calls.push(
                    @openai.build_tool_call_json(openai_id, name, args),
                  )
                  tool_call_counter = tool_call_counter + 1
                }
                _ => ()
              }
            }
          _ => ()
        }
        let content = texts
          .iter()
          .fold(init="", fn(acc, t) {
            if acc == "" {
              t
            } else {
              acc + "\n\n" + t
            }
          })
        choices.push(@openai.build_chat_choice(idx, content, tool_calls))
        idx = idx + 1
      }
    _ => ()
  }
  let id = "gemini-" + idx.to_string()
  @openai.build_chat_response(id, "gemini", choices)
}

///|
/// Transform OpenAI Chat Completions response to Gemini GenerateContent format.
/// Handles both text and tool_calls.
pub fn chat_response_to_gemini(body : String) -> String {
  let json = @json.parse(body) catch { _ => return body }
  let parts : Array[Json] = []
  match json {
    { "choices": Array(choices), .. } =>
      match choices.get(0) {
        Some(choice) => {
          // Text content
          match choice {
            { "message": { "content": String(c), .. }, .. } =>
              if not(c.is_empty()) {
                let p : Map[String, Json] = {}
                p["text"] = Json::string(c)
                parts.push(Json::object(p))
              }
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
                    let args : Json = @json.parse(args_str) catch { _ => {} }
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
    let p : Map[String, Json] = {}
    p["text"] = Json::string("")
    parts.push(Json::object(p))
  }
  let content : Map[String, Json] = {}
  content["parts"] = Json::array(parts)
  content["role"] = Json::string("model")
  let candidate : Map[String, Json] = {}
  candidate["content"] = Json::object(content)
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
/// Transform OpenAI error to Gemini error format
pub fn openai_error_to_gemini(body : String) -> String {
  let json = @json.parse(body) catch { _ => return body }
  let message = match json {
    { "error": { "message": String(msg), .. }, .. } => msg
    _ => "Unknown error"
  }
  let result : Map[String, Json] = {}
  let error : Map[String, Json] = {}
  error["code"] = Json::number(400.0)
  error["message"] = Json::string(message)
  error["status"] = Json::string("INVALID_ARGUMENT")
  result["error"] = Json::object(error)
  Json::object(result).stringify()
}

