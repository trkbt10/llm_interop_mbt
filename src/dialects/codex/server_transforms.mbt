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
pub fn chat_response_to_events(
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
  for event in build_turn_stream_start_events(turn_id, item_id) {
    events.push(event)
  }
  events.push(build_turn_stream_delta_event(item_id, content))
  for
    event in build_turn_stream_success_events(
      turn_id, item_id, content, input_tokens, output_tokens, total_tokens,
    ) {
    events.push(event)
  }
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
/// Canonical app-server entrypoint:
/// emit the initial Codex turn/item start events before streaming deltas.
pub fn build_turn_stream_start_events(
  turn_id : String,
  item_id : String,
) -> Array[String] {
  [make_turn_started_event(turn_id), make_item_started_event(item_id)]
}

///|
/// Canonical app-server entrypoint:
/// wrap a streamed text delta as a Codex event.
pub fn build_turn_stream_delta_event(
  item_id : String,
  delta : String,
) -> String {
  make_agent_message_delta_event(item_id, delta)
}

///|
/// Canonical app-server entrypoint:
/// emit the final success tail for a streamed turn.
pub fn build_turn_stream_success_events(
  turn_id : String,
  item_id : String,
  content : String,
  input_tokens : Int,
  output_tokens : Int,
  total_tokens : Int,
) -> Array[String] {
  [
    make_item_completed_event(item_id, content),
    make_token_usage_event(input_tokens, output_tokens, total_tokens),
    make_turn_completed_event(turn_id, item_id, content),
  ]
}

///|
/// Canonical app-server entrypoint:
/// emit a start+failed sequence when the turn cannot begin at all.
pub fn build_turn_start_failure_events(
  turn_id : String,
  error_msg : String,
) -> Array[String] {
  [make_turn_started_event(turn_id), make_turn_failed_event(turn_id, error_msg)]
}

///|
/// Canonical app-server entrypoint:
/// emit a failed turn event after streaming already started.
pub fn build_turn_stream_failure_event(
  turn_id : String,
  error_msg : String,
) -> String {
  make_turn_failed_event(turn_id, error_msg)
}

///|
/// Build turn/started event
fn make_turn_started_event(turn_id : String) -> String {
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
fn make_item_started_event(item_id : String) -> String {
  let event : Json = {
    "method": "item/started",
    "params": { "item": { "type": "agentMessage", "id": item_id, "text": "" } },
  }
  event.stringify()
}

///|
/// Build item/agentMessage/delta event
fn make_agent_message_delta_event(item_id : String, delta : String) -> String {
  let event : Json = {
    "method": "item/agentMessage/delta",
    "params": { "itemId": item_id, "delta": delta },
  }
  event.stringify()
}

///|
/// Build item/completed event for agentMessage
fn make_item_completed_event(item_id : String, content : String) -> String {
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
fn make_token_usage_event(
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
fn make_turn_completed_event(
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
fn make_turn_failed_event(turn_id : String, error_msg : String) -> String {
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
  build_turn_start_failure_events(turn_id, error_message)
}
