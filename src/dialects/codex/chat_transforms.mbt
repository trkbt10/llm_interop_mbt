///|
/// Codex ↔ OpenAI Chat Completions request/response transforms
///
/// Request direction: OpenAI messages → Codex intermediate format (prompt extraction)
/// Response direction: Codex JSONL events (aggregated) → OpenAI Chat Completion response

// =============================================================================
// Request transform: OpenAI → Codex intermediate format
// =============================================================================

///|
/// Transform an OpenAI Chat Completion request into a Codex intermediate format.
/// Extracts the conversation into a prompt string that prepare_codex_upstream
/// will use to build a JSON-RPC turn/start message.
pub fn chat_request_to_protocol(
  body : String,
  _ctx : @types.TransformContext,
) -> String {
  let json = @json.parse(body) catch { _ => return body }
  let model = match json {
    { "model": String(m), .. } => m
    _ => "codex"
  }
  let messages = match json {
    { "messages": Array(msgs), .. } => msgs
    _ => return body
  }
  // Build prompt from all messages, preserving conversation context
  let prompt = build_prompt_from_messages(messages)
  let effort : String? = match json {
    { "reasoning_effort": String(e), .. } => Some(e)
    _ => None
  }
  let obj : Map[String, Json] = {}
  obj["prompt"] = Json::string(prompt)
  obj["model"] = Json::string(model)
  match effort {
    Some(e) => obj["effort"] = Json::string(e)
    None => ()
  }
  // Preserve the full messages array for richer turn input in the future
  obj["messages"] = Json::array(messages)
  Json::object(obj).stringify()
}

///|
/// Build a prompt string from OpenAI messages.
/// Uses the last user message as the primary prompt.
/// If there's a system message, prepends it as context.
fn build_prompt_from_messages(messages : Array[Json]) -> String {
  let mut system_msg = ""
  let mut last_user_msg = ""
  for msg in messages {
    match msg {
      { "role": String("system"), "content": String(text), .. } =>
        system_msg = text
      { "role": String("user"), "content": String(text), .. } =>
        last_user_msg = text
      { "role": String("user"), "content": Array(parts), .. } => {
        // Multipart content — extract text parts
        let buf = StringBuilder::new()
        for part in parts {
          match part {
            { "type": String("text"), "text": String(t), .. } => {
              if buf.to_string().length() > 0 {
                buf.write_string("\n")
              }
              buf.write_string(t)
            }
            _ => ()
          }
        }
        last_user_msg = buf.to_string()
      }
      _ => ()
    }
  }
  if system_msg != "" && last_user_msg != "" {
    system_msg + "\n\n" + last_user_msg
  } else if last_user_msg != "" {
    last_user_msg
  } else {
    system_msg
  }
}

// =============================================================================
// Response transform: Codex events → OpenAI Chat Completion
// =============================================================================

///|
/// Intermediate accumulator for collecting data from Codex events
priv struct EventAccumulator {
  mut content : String
  mut reasoning_text : String
  mut turn_id : String
  mut thread_id : String
  model : String
  mut finish_reason : String
  mut input_tokens : Int
  mut output_tokens : Int
  mut total_tokens : Int
  mut cached_input_tokens : Int
  mut reasoning_output_tokens : Int
  mut has_error : Bool
  mut error_message : String
  /// Tool calls collected from events
  tool_calls : Array[Json]
}

///|
fn EventAccumulator::new() -> EventAccumulator {
  {
    content: "",
    reasoning_text: "",
    turn_id: "",
    thread_id: "",
    model: "codex",
    finish_reason: "stop",
    input_tokens: 0,
    output_tokens: 0,
    total_tokens: 0,
    cached_input_tokens: 0,
    reasoning_output_tokens: 0,
    has_error: false,
    error_message: "",
    tool_calls: [],
  }
}

///|
/// Transform Codex aggregated events (JSON array string) into an OpenAI
/// Chat Completion response. The host transport collects JSONL events
/// into a JSON array before calling this function.
pub fn events_to_chat(events_json : String) -> String {
  let events = @json.parse(events_json) catch { _ => return events_json }
  let items = match events {
    Array(arr) => arr
    _ => return events_json
  }
  let acc = EventAccumulator::new()
  for event in items {
    process_event(acc, event)
  }
  build_openai_response(acc)
}

///|
/// Alias for transform_response dispatch.
pub fn response_to_chat(events_json : String) -> String {
  events_to_chat(events_json)
}

///|
/// Process a single Codex event and update the accumulator.
fn process_event(acc : EventAccumulator, event : Json) -> Unit {
  let rpc_method = match event {
    { "method": String(m), .. } => m
    _ => return
  }
  match rpc_method {
    // --- Streaming text deltas ---
    "item/agentMessage/delta" =>
      match event {
        { "params": { "delta": String(delta), .. }, .. } =>
          acc.content = acc.content + delta
        _ => ()
      }
    // codex/event/agent_message_content_delta is ignored —
    // item/agentMessage/delta carries the same data and we use that exclusively
    // to avoid double-counting
    "codex/event/agent_message_content_delta" => ()
    // --- Final agent message (fallback if no deltas) ---
    "codex/event/agent_message" =>
      if acc.content == "" {
        match event {
          { "params": { "msg": { "message": String(msg), .. }, .. }, .. } =>
            acc.content = msg
          _ => ()
        }
      }
    // --- Task complete with last_agent_message (final fallback) ---
    "codex/event/task_complete" =>
      if acc.content == "" {
        match event {
          {
            "params": { "msg": { "last_agent_message": String(msg), .. }, .. },
            ..
          } => acc.content = msg
          _ => ()
        }
      }
    // --- Turn completion ---
    "turn/completed" => {
      match event {
        { "params": { "turn": { "id": String(id), .. }, .. }, .. } =>
          acc.turn_id = id
        _ => ()
      }
      match event {
        { "params": { "turn": { "status": String(status), .. }, .. }, .. } =>
          acc.finish_reason = codex_status_to_finish_reason(status)
        _ => ()
      }
      match event {
        { "params": { "turn": { "error": String(err_msg), .. }, .. }, .. } => {
          acc.has_error = true
          acc.error_message = err_msg
        }
        _ => ()
      }
    }
    // --- Thread started (extract model info) ---
    "thread/started" =>
      match event {
        { "params": { "thread": { "id": String(tid), .. }, .. }, .. } =>
          acc.thread_id = tid
        _ => ()
      }
    // --- Token usage (public API, camelCase) ---
    "thread/tokenUsage/updated" =>
      match event {
        { "params": { "tokenUsage": token_usage, .. }, .. } =>
          extract_token_usage(acc, token_usage)
        _ => ()
      }
    // --- Token usage (codex internal, snake_case) ---
    "codex/event/token_count" =>
      // Only use if thread/tokenUsage/updated hasn't been processed
      if acc.total_tokens == 0 {
        match event {
          { "params": { "msg": msg, .. }, .. } =>
            // Pass the full msg object — CodexTokenUsage::from_json handles
            // Format 2: { "info": { "total_token_usage": { ... } } }
            match CodexTokenUsage::from_json(msg) {
              Some(usage) => apply_token_usage(acc, usage)
              None => ()
            }
          _ => ()
        }
      }
    // --- Item completed: extract reasoning content ---
    "item/completed" =>
      match event {
        {
          "params": { "item": { "type": String("reasoning"), .. } as item, .. },
          ..
        } => extract_reasoning(acc, item)
        _ => ()
      }
    // --- Error response from JSON-RPC ---
    "codex/event/task_started" =>
      // Extract model context window for metadata
      match event {
        {
          "params": { "msg": { "model_context_window": Number(w, ..), .. }, .. },
          ..
        } => ignore(w)
        _ => ()
      }
    _ => () // Ignore events we don't need for the response
  }
}

///|
/// Map Codex turn status to OpenAI finish_reason.
fn codex_status_to_finish_reason(status : String) -> String {
  match status {
    "completed" => "stop"
    "interrupted" => "stop"
    "failed" => "stop"
    "inProgress" => "length" // Shouldn't happen at completion, but handle gracefully
    _ => "stop"
  }
}

///|
/// Extract token usage from thread/tokenUsage/updated params.
fn extract_token_usage(acc : EventAccumulator, token_usage : Json) -> Unit {
  match CodexTokenUsage::from_json(token_usage) {
    Some(usage) => apply_token_usage(acc, usage)
    None => ()
  }
}

///|
fn apply_token_usage(acc : EventAccumulator, usage : CodexTokenUsage) -> Unit {
  acc.input_tokens = usage.input_tokens
  acc.output_tokens = usage.output_tokens
  acc.total_tokens = usage.total_tokens
  acc.cached_input_tokens = usage.cached_input_tokens
  acc.reasoning_output_tokens = usage.reasoning_output_tokens
}

///|
/// Extract reasoning content from a completed reasoning item.
fn extract_reasoning(acc : EventAccumulator, item : Json) -> Unit {
  match item {
    { "summary": Array(summaries), .. } =>
      for s in summaries {
        match s {
          { "text": String(text), .. } =>
            if acc.reasoning_text == "" {
              acc.reasoning_text = text
            } else {
              acc.reasoning_text = acc.reasoning_text + "\n" + text
            }
          String(text) =>
            if acc.reasoning_text == "" {
              acc.reasoning_text = text
            } else {
              acc.reasoning_text = acc.reasoning_text + "\n" + text
            }
          _ => ()
        }
      }
    _ => ()
  }
}

// =============================================================================
// OpenAI response builder
// =============================================================================

///|
/// Build an OpenAI Chat Completion response from accumulated event data.
fn build_openai_response(acc : EventAccumulator) -> String {
  // If an error occurred, return error format
  if acc.has_error && acc.error_message != "" {
    let err : Json = {
      "error": {
        "message": acc.error_message,
        "type": "codex_error",
        "code": "turn_failed",
      },
    }
    return err.stringify()
  }
  let id = if acc.turn_id != "" {
    "codex-" + acc.turn_id
  } else if acc.thread_id != "" {
    "codex-" + acc.thread_id
  } else {
    "codex-response"
  }
  // Build the message content
  let message : Map[String, Json] = {}
  message["role"] = Json::string("assistant")
  message["content"] = Json::string(acc.content)
  // Add tool_calls if present
  if acc.tool_calls.length() > 0 {
    message["tool_calls"] = Json::array(acc.tool_calls)
  }
  // Build the choice
  let choice : Map[String, Json] = {}
  choice["index"] = Json::number(0.0)
  choice["message"] = Json::object(message)
  choice["finish_reason"] = Json::string(acc.finish_reason)
  // Build usage
  let usage : Map[String, Json] = {}
  usage["prompt_tokens"] = Json::number(acc.input_tokens.to_double())
  usage["completion_tokens"] = Json::number(acc.output_tokens.to_double())
  usage["total_tokens"] = Json::number(acc.total_tokens.to_double())
  if acc.cached_input_tokens > 0 {
    usage["cached_tokens"] = Json::number(acc.cached_input_tokens.to_double())
  }
  if acc.reasoning_output_tokens > 0 {
    usage["reasoning_tokens"] = Json::number(
      acc.reasoning_output_tokens.to_double(),
    )
  }
  // Build top-level response
  let result : Map[String, Json] = {}
  result["id"] = Json::string(id)
  result["object"] = Json::string("chat.completion")
  result["model"] = Json::string(acc.model)
  result["choices"] = Json::array([Json::object(choice)])
  result["usage"] = Json::object(usage)
  Json::object(result).stringify()
}
