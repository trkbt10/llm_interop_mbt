///|
/// Chat Completions request/response transformations: Anthropic <-> OpenAI
///
/// Transforms requests and responses between OpenAI Chat Completions
/// and Anthropic Messages formats, plus error format conversions.

///|
/// Transform Anthropic Messages request to OpenAI Chat Completions format
pub fn request_to_chat(
  body : String,
  ctx : @types.TransformContext,
) -> String {
  let json = @json.parse(body) catch { _ => return body }
  let result : Map[String, Json] = {}
  // Copy model
  match json {
    { "model": model, .. } => result["model"] = model
    _ => ()
  }
  // Extract and apply generation parameters
  @types.GenerationParams::from_anthropic(json).apply_to_openai(result, ctx)
  // Build messages array
  let messages : Array[Json] = []
  // Add system message if present
  match json {
    { "system": String(system), .. } => {
      let sys_msg : Map[String, Json] = {}
      sys_msg["role"] = Json::string("system")
      sys_msg["content"] = Json::string(system)
      messages.push(Json::object(sys_msg))
    }
    _ => ()
  }
  // Convert messages
  match json {
    { "messages": Array(msgs), .. } =>
      for msg in msgs {
        match msg {
          { "role": String(role), "content": content, .. } => {
            let new_msg : Map[String, Json] = {}
            new_msg["role"] = Json::string(role)
            new_msg["content"] = transform_anthropic_content_to_openai(content)
            messages.push(Json::object(new_msg))
          }
          _ => ()
        }
      }
    _ => ()
  }
  result["messages"] = Json::array(messages)
  Json::object(result).stringify()
}

///|
/// Transform Anthropic content to OpenAI content format
fn transform_anthropic_content_to_openai(content : Json) -> Json {
  match content {
    String(_) => content
    Array(parts) => {
      let openai_parts : Array[Json] = []
      for part in parts {
        match part {
          { "type": String("text"), "text": String(text), .. } => {
            let p : Map[String, Json] = {}
            p["type"] = Json::string("text")
            p["text"] = Json::string(text)
            openai_parts.push(Json::object(p))
          }
          {
            "type": String("image"),
            "source": { "data": String(data), "media_type": String(mt), .. },
            ..
          } => {
            let p : Map[String, Json] = {}
            p["type"] = Json::string("image_url")
            let url = "data:" + mt + ";base64," + data
            p["image_url"] = Json::object({ "url": Json::string(url) })
            openai_parts.push(Json::object(p))
          }
          _ => ()
        }
      }
      Json::array(openai_parts)
    }
    _ => content
  }
}

///|
/// Transform OpenAI Chat Completions request to Anthropic Messages format
pub fn chat_request_to_anthropic(
  body : String,
  ctx : @types.TransformContext,
) -> String {
  let json = @json.parse(body) catch { _ => return body }
  let result : Map[String, Json] = {}
  // Copy model
  match json {
    { "model": model, .. } => result["model"] = model
    _ => ()
  }
  // Extract and apply generation parameters (includes max_tokens default)
  @types.GenerationParams::from_openai(json).apply_to_anthropic(result, ctx)
  // Extract system message and convert messages
  let messages : Array[Json] = []
  match json {
    { "messages": Array(msgs), .. } =>
      for msg in msgs {
        match msg {
          { "role": String("system"), "content": String(content), .. } =>
            result["system"] = Json::string(content)
          // Assistant with tool_calls → Anthropic tool_use content blocks
          {
            "role": String("assistant"),
            "tool_calls": Array(tool_calls),
            ..
          } => {
            let blocks : Array[Json] = []
            // Include text content if present
            match msg {
              { "content": String(c), .. } =>
                if not(c.is_empty()) {
                  let tb : Map[String, Json] = {}
                  tb["type"] = Json::string("text")
                  tb["text"] = Json::string(c)
                  blocks.push(Json::object(tb))
                }
              _ => ()
            }
            // Convert each tool_call to tool_use block
            for tc in tool_calls {
              match tc {
                {
                  "id": String(tc_id),
                  "function": {
                    "name": String(name),
                    "arguments": String(args_str),
                    ..
                  },
                  ..
                } => {
                  let input : Json = @json.parse(args_str) catch { _ => {} }
                  let anthropic_id = @interop_util.openai_chat_to_anthropic_tool_use_id(tc_id)
                  let tb : Map[String, Json] = {}
                  tb["type"] = Json::string("tool_use")
                  tb["id"] = Json::string(anthropic_id)
                  tb["name"] = Json::string(name)
                  tb["input"] = input
                  blocks.push(Json::object(tb))
                }
                _ => ()
              }
            }
            let new_msg : Map[String, Json] = {}
            new_msg["role"] = Json::string("assistant")
            new_msg["content"] = Json::array(blocks)
            messages.push(Json::object(new_msg))
          }
          // Tool result → Anthropic user message with tool_result content block
          {
            "role": String("tool"),
            "content": String(content),
            "tool_call_id": String(tc_id),
            ..
          } => {
            let anthropic_id = @interop_util.openai_chat_to_anthropic_tool_use_id(tc_id)
            let block : Map[String, Json] = {}
            block["type"] = Json::string("tool_result")
            block["tool_use_id"] = Json::string(anthropic_id)
            block["content"] = Json::string(content)
            let new_msg : Map[String, Json] = {}
            new_msg["role"] = Json::string("user")
            new_msg["content"] = Json::array([Json::object(block)])
            messages.push(Json::object(new_msg))
          }
          // Regular messages (user, etc.)
          { "role": String(role), "content": content, .. } => {
            let new_msg : Map[String, Json] = {}
            new_msg["role"] = Json::string(role)
            new_msg["content"] = transform_openai_content_to_anthropic(content)
            messages.push(Json::object(new_msg))
          }
          _ => ()
        }
      }
    _ => ()
  }
  result["messages"] = Json::array(messages)
  // Convert tools: OpenAI function tools → Anthropic tools
  match json {
    { "tools": Array(openai_tools), .. } => {
      let anthropic_tools : Array[Json] = []
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
            let t : Map[String, Json] = {}
            t["name"] = Json::string(name)
            t["description"] = Json::string(desc)
            t["input_schema"] = params
            anthropic_tools.push(Json::object(t))
          }
          _ => ()
        }
      }
      if anthropic_tools.length() > 0 {
        result["tools"] = Json::array(anthropic_tools)
      }
    }
    _ => ()
  }
  Json::object(result).stringify()
}

///|
/// Transform OpenAI content to Anthropic content format
fn transform_openai_content_to_anthropic(content : Json) -> Json {
  match content {
    String(_) => content
    Array(parts) => {
      let anthropic_parts : Array[Json] = []
      for part in parts {
        match part {
          { "type": String("text"), "text": String(text), .. } => {
            let p : Map[String, Json] = {}
            p["type"] = Json::string("text")
            p["text"] = Json::string(text)
            anthropic_parts.push(Json::object(p))
          }
          {
            "type": String("image_url"),
            "image_url": { "url": String(url), .. },
            ..
          } =>
            match @utils.parse_data_url(url) {
              Some((media_type, data)) => {
                let source : Map[String, Json] = {}
                source["type"] = Json::string("base64")
                source["media_type"] = Json::string(media_type)
                source["data"] = Json::string(data)
                let p : Map[String, Json] = {}
                p["type"] = Json::string("image")
                p["source"] = Json::object(source)
                anthropic_parts.push(Json::object(p))
              }
              None => ()
            }
          _ => ()
        }
      }
      Json::array(anthropic_parts)
    }
    _ => content
  }
}

///|
/// Transform Anthropic Messages response to OpenAI Chat Completions format.
/// Handles both text and tool_use content blocks.
pub fn response_to_chat(body : String) -> String {
  let json = @json.parse(body) catch { _ => return body }
  let id = match json {
    { "id": String(id), .. } => id
    _ => ""
  }
  let model = match json {
    { "model": String(m), .. } => m
    _ => ""
  }
  // Extract text and tool_use blocks
  let texts : Array[String] = []
  let tool_calls : Array[Json] = []
  match json {
    { "content": Array(blocks), .. } =>
      for block in blocks {
        match block {
          { "type": String("text"), "text": String(t), .. } => texts.push(t)
          {
            "type": String("tool_use"),
            "id": String(tool_id),
            "name": String(name),
            "input": input,
            ..
          } => {
            let openai_id = @interop_util.anthropic_to_openai_chat_call_id(tool_id)
            tool_calls.push(@openai.build_tool_call_json(openai_id, name, input))
          }
          _ => ()
        }
      }
    _ => ()
  }
  let content = texts
    .iter()
    .fold(init="", fn(acc, t) { if acc == "" { t } else { acc + "\n\n" + t } })
  let choice = @openai.build_chat_choice(0, content, tool_calls)
  @openai.build_chat_response(id, model, [choice])
}

///|
/// Transform OpenAI Chat Completions response to Anthropic Messages format.
/// Handles both text and tool_calls.
pub fn chat_response_to_anthropic(body : String) -> String {
  let json = @json.parse(body) catch { _ => return body }
  let id = match json {
    { "id": String(id), .. } => id
    _ => "msg-gateway"
  }
  let model = match json {
    { "model": String(m), .. } => m
    _ => ""
  }
  // Extract content and tool_calls from first choice
  let content_blocks : Array[Json] = []
  let mut stop_reason = "end_turn"
  match json {
    { "choices": Array(choices), .. } =>
      match choices.get(0) {
        Some(choice) => {
          // Text content
          match choice {
            { "message": { "content": String(c), .. }, .. } =>
              if not(c.is_empty()) {
                let text_block : Map[String, Json] = {}
                text_block["type"] = Json::string("text")
                text_block["text"] = Json::string(c)
                content_blocks.push(Json::object(text_block))
              }
            _ => ()
          }
          // Tool calls
          match choice {
            { "message": { "tool_calls": Array(tcs), .. }, .. } =>
              for tc in tcs {
                match tc {
                  {
                    "id": String(tc_id),
                    "function": {
                      "name": String(name),
                      "arguments": String(args_str),
                      ..
                    },
                    ..
                  } => {
                    let input : Json = @json.parse(args_str) catch { _ => {} }
                    let anthropic_id = @interop_util.openai_chat_to_anthropic_tool_use_id(tc_id)
                    let tool_block : Map[String, Json] = {}
                    tool_block["type"] = Json::string("tool_use")
                    tool_block["id"] = Json::string(anthropic_id)
                    tool_block["name"] = Json::string(name)
                    tool_block["input"] = input
                    content_blocks.push(Json::object(tool_block))
                    stop_reason = "tool_use"
                  }
                  _ => ()
                }
              }
            _ => ()
          }
          // Finish reason override
          match choice {
            { "finish_reason": String("tool_calls"), .. } =>
              stop_reason = "tool_use"
            _ => ()
          }
        }
        _ => ()
      }
    _ => ()
  }
  if content_blocks.is_empty() {
    let text_block : Map[String, Json] = {}
    text_block["type"] = Json::string("text")
    text_block["text"] = Json::string("")
    content_blocks.push(Json::object(text_block))
  }
  let result : Map[String, Json] = {}
  result["id"] = Json::string(id)
  result["type"] = Json::string("message")
  result["role"] = Json::string("assistant")
  result["model"] = Json::string(model)
  result["content"] = Json::array(content_blocks)
  result["stop_reason"] = Json::string(stop_reason)
  result["stop_sequence"] = Json::null()
  result["usage"] = Json::object({
    "input_tokens": Json::number(0.0),
    "output_tokens": Json::number(0.0),
  })
  Json::object(result).stringify()
}

///|
/// Transform Anthropic error to OpenAI error format
pub fn error_to_openai(error_obj : Json) -> String {
  let message = match error_obj {
    { "message": String(msg), .. } => msg
    _ => "Unknown error"
  }
  let error_type = match error_obj {
    { "type": String(t), .. } => t
    _ => "api_error"
  }
  let result : Map[String, Json] = {}
  let error : Map[String, Json] = {}
  error["message"] = Json::string(message)
  error["type"] = Json::string(error_type)
  result["error"] = Json::object(error)
  Json::object(result).stringify()
}

///|
/// Transform Anthropic error to Gemini error format
pub fn error_to_gemini(error_obj : Json) -> String {
  let message = match error_obj {
    { "message": String(msg), .. } => msg
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

///|
/// Transform OpenAI error to Anthropic error format
pub fn openai_error_to_anthropic(body : String) -> String {
  let json = @json.parse(body) catch { _ => return body }
  let message = match json {
    { "error": { "message": String(msg), .. }, .. } => msg
    _ => "Unknown error"
  }
  let error_type = match json {
    { "error": { "type": String(t), .. }, .. } => t
    _ => "api_error"
  }
  let result : Map[String, Json] = {}
  result["type"] = Json::string("error")
  let error : Map[String, Json] = {}
  error["type"] = Json::string(error_type)
  error["message"] = Json::string(message)
  result["error"] = Json::object(error)
  Json::object(result).stringify()
}

///|
/// Check if response is an Anthropic error format
pub fn is_error(json : Json) -> Bool {
  match json {
    { "type": String("error"), "error": _, .. } => true
    _ => false
  }
}

///|
/// Check if response is an OpenAI error format
pub fn is_openai_error(json : Json) -> Bool {
  match json {
    { "error": { "message": String(_), .. }, .. } => true
    _ => false
  }
}

///|
/// Extract error object from Anthropic error response
pub fn extract_error(json : Json) -> Json? {
  match json {
    { "type": String("error"), "error": error_obj, .. } => Some(error_obj)
    _ => None
  }
}

