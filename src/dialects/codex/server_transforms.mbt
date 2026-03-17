///|
/// OpenAI Chat Completion response → Codex app-server event sequence
///
/// This is the inverse of chat_transforms.mbt:
///   chat_transforms: Codex events → OpenAI response
///   server_transforms: OpenAI response → Codex events
///
/// Used by cmd/app-server to convert backend responses into
/// the event stream that Codex clients expect.

///|
/// Convert an OpenAI Chat Completion response JSON string into an array of
/// Codex app-server event JSONL strings.
///
/// On success, produces 6 events:
///   1. turn/started
///   2. item/started (agentMessage)
///   3. item/agentMessage/delta
///   4. item/completed (agentMessage)
///   5. thread/tokenUsage/updated
///   6. turn/completed
///
/// On error, produces 2 events:
///   1. turn/started (inProgress)
///   2. turn/completed (failed)
pub fn chat_response_to_codex_events(
  response_body : String,
  thread_id : String,
  turn_id : String,
  item_id : String,
) -> Array[String] {
  let json = @json.parse(response_body) catch {
    _ =>
      return make_error_events(
        thread_id, turn_id, "Failed to parse response JSON",
      )
  }
  // Check for error response
  match json {
    { "error": { "message": String(msg), .. }, .. } =>
      return make_error_events(thread_id, turn_id, msg)
    _ => ()
  }
  // Extract assistant content
  let content = match json {
    { "choices": [{ "message": { "content": String(text), .. }, .. }, ..], .. } =>
      text
    _ => ""
  }
  // Extract token usage
  let input_tokens = match json {
    { "usage": { "prompt_tokens": Number(n, ..), .. }, .. } => n.to_int()
    _ => 0
  }
  let output_tokens = match json {
    { "usage": { "completion_tokens": Number(n, ..), .. }, .. } => n.to_int()
    _ => 0
  }
  let total_tokens = match json {
    { "usage": { "total_tokens": Number(n, ..), .. }, .. } => n.to_int()
    _ => input_tokens + output_tokens
  }
  // Build event sequence
  let events : Array[String] = []
  // 1. turn/started
  let turn_started : Json = {
    "method": "turn/started",
    "params": {
      "turn": {
        "id": turn_id,
        "status": "inProgress",
        "items": Json::array([]),
      },
    },
  }
  events.push(turn_started.stringify())
  // 2. item/started
  let item_started : Json = {
    "method": "item/started",
    "params": { "item": { "type": "agentMessage", "id": item_id, "text": "" } },
  }
  events.push(item_started.stringify())
  // 3. item/agentMessage/delta
  let delta : Json = {
    "method": "item/agentMessage/delta",
    "params": { "itemId": item_id, "delta": content },
  }
  events.push(delta.stringify())
  // 4. item/completed
  let item_completed : Json = {
    "method": "item/completed",
    "params": {
      "item": { "type": "agentMessage", "id": item_id, "text": content },
    },
  }
  events.push(item_completed.stringify())
  // 5. thread/tokenUsage/updated
  let token_usage : Json = {
    "method": "thread/tokenUsage/updated",
    "params": {
      "tokenUsage": {
        "total": {
          "inputTokens": input_tokens,
          "outputTokens": output_tokens,
          "totalTokens": total_tokens,
        },
      },
    },
  }
  events.push(token_usage.stringify())
  // 6. turn/completed
  let completed_item : Json = {
    "type": "agentMessage",
    "id": item_id,
    "text": content,
  }
  let turn_completed : Json = {
    "method": "turn/completed",
    "params": {
      "turn": {
        "id": turn_id,
        "status": "completed",
        "items": Json::array([completed_item]),
      },
    },
  }
  events.push(turn_completed.stringify())
  events
}

// =============================================================================
// Streaming SSE helpers
// =============================================================================

///|
/// Extract delta content from an OpenAI SSE chunk JSON and wrap as Codex
/// item/agentMessage/delta event. Returns None if no content delta.
pub fn sse_chunk_to_codex_delta(sse_data : Json, item_id : String) -> String? {
  let delta_text = match sse_data {
    { "choices": [{ "delta": { "content": String(text), .. }, .. }, ..], .. } =>
      text
    _ => return None
  }
  if delta_text == "" {
    return None
  }
  let event : Json = {
    "method": "item/agentMessage/delta",
    "params": { "itemId": item_id, "delta": delta_text },
  }
  Some(event.stringify())
}

///|
/// Extract token usage from an OpenAI SSE final chunk (usage field).
/// Returns None if no usage info.
pub fn sse_chunk_extract_usage(sse_data : Json) -> (Int, Int, Int)? {
  match sse_data {
    {
      "usage": {
        "prompt_tokens": Number(input, ..),
        "completion_tokens": Number(output, ..),
        "total_tokens": Number(total, ..),
        ..
      },
      ..
    } => Some((input.to_int(), output.to_int(), total.to_int()))
    _ => None
  }
}

///|
/// Build turn/started event
pub fn make_turn_started_event(turn_id : String) -> String {
  let event : Json = {
    "method": "turn/started",
    "params": {
      "turn": {
        "id": turn_id,
        "status": "inProgress",
        "items": Json::array([]),
      },
    },
  }
  event.stringify()
}

///|
/// Build item/started event for agentMessage
pub fn make_item_started_event(item_id : String) -> String {
  let event : Json = {
    "method": "item/started",
    "params": { "item": { "type": "agentMessage", "id": item_id, "text": "" } },
  }
  event.stringify()
}

///|
/// Build item/completed event for agentMessage
pub fn make_item_completed_event(item_id : String, content : String) -> String {
  let event : Json = {
    "method": "item/completed",
    "params": {
      "item": { "type": "agentMessage", "id": item_id, "text": content },
    },
  }
  event.stringify()
}

///|
/// Build thread/tokenUsage/updated event
pub fn make_token_usage_event(
  input_tokens : Int,
  output_tokens : Int,
  total_tokens : Int,
) -> String {
  let event : Json = {
    "method": "thread/tokenUsage/updated",
    "params": {
      "tokenUsage": {
        "total": {
          "inputTokens": input_tokens,
          "outputTokens": output_tokens,
          "totalTokens": total_tokens,
        },
      },
    },
  }
  event.stringify()
}

///|
/// Build turn/completed event (success)
pub fn make_turn_completed_event(
  turn_id : String,
  item_id : String,
  content : String,
) -> String {
  let completed_item : Json = {
    "type": "agentMessage",
    "id": item_id,
    "text": content,
  }
  let event : Json = {
    "method": "turn/completed",
    "params": {
      "turn": {
        "id": turn_id,
        "status": "completed",
        "items": Json::array([completed_item]),
      },
    },
  }
  event.stringify()
}

///|
/// Build turn/completed event (failed)
pub fn make_turn_failed_event(turn_id : String, error_msg : String) -> String {
  let event : Json = {
    "method": "turn/completed",
    "params": {
      "turn": {
        "id": turn_id,
        "status": "failed",
        "error": { "message": error_msg },
      },
    },
  }
  event.stringify()
}

///|
/// Generate error event sequence: turn/started (inProgress) + turn/completed (failed)
fn make_error_events(
  _thread_id : String,
  turn_id : String,
  error_message : String,
) -> Array[String] {
  let turn_started : Json = {
    "method": "turn/started",
    "params": {
      "turn": {
        "id": turn_id,
        "status": "inProgress",
        "items": Json::array([]),
      },
    },
  }
  let turn_completed : Json = {
    "method": "turn/completed",
    "params": {
      "turn": {
        "id": turn_id,
        "status": "failed",
        "error": { "message": error_message },
      },
    },
  }
  [turn_started.stringify(), turn_completed.stringify()]
}
