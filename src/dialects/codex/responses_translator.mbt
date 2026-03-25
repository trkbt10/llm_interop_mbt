///|
/// Codex JSONL event stream -> OpenAI Responses SSE translator.
///
/// Codex is not an SSE protocol, but its stdio JSONL event stream is already
/// incremental. This translator treats each event line as a streaming chunk and
/// emits canonical Responses SSE events without routing through OpenAI Chat.

///|
struct CodexToResponsesTranslator {
  response_id : String
  model : String
  mut next_output_index : Int
  mut has_emitted_created : Bool
  mut has_emitted_in_progress : Bool
  mut has_open_message : Bool
  mut current_message_output_index : Int
  mut current_message_item_id : String
  mut current_message_text : String
  mut input_tokens : Int
  mut output_tokens : Int
  mut total_tokens : Int
  completed_output : Array[Json]
}

///|
pub fn CodexToResponsesTranslator::new(
  response_id~ : String,
  model? : String = "",
) -> CodexToResponsesTranslator {
  {
    response_id,
    model,
    next_output_index: 0,
    has_emitted_created: false,
    has_emitted_in_progress: false,
    has_open_message: false,
    current_message_output_index: -1,
    current_message_item_id: "",
    current_message_text: "",
    input_tokens: 0,
    output_tokens: 0,
    total_tokens: 0,
    completed_output: [],
  }
}

///|
pub fn CodexToResponsesTranslator::translate(
  self : CodexToResponsesTranslator,
  event : @sse.SseEvent,
) -> Array[(String, Json)] {
  let events : Array[(String, Json)] = []
  self.emit_lifecycle(events)
  match event.data {
    {
      "method": String("item/agentMessage/delta"),
      "params": { "delta": String(delta), .. },
      ..
    } =>
      if delta.length() > 0 {
        self.ensure_message_started(events)
        self.current_message_text = self.current_message_text + delta
        events.push(
          (
            "response.output_text.delta",
            {
              "type": "response.output_text.delta",
              "delta": delta,
              "content_index": 0,
              "item_id": self.current_message_item_id,
              "output_index": self.current_message_output_index,
            },
          ),
        )
      }
    {
      "method": String("codex/event/agent_message"),
      "params": { "msg": { "message": String(message), .. }, .. },
      ..
    } => self.emit_fallback_text(events, message)
    {
      "method": String("codex/event/task_complete"),
      "params": { "msg": { "last_agent_message": String(message), .. }, .. },
      ..
    } => self.emit_fallback_text(events, message)
    {
      "method": String("item/completed"),
      "params": { "item": { "text": String(text), .. }, .. },
      ..
    } => {
      self.emit_fallback_text(events, text)
      self.close_current_message(events)
    }
    {
      "method": String("thread/tokenUsage/updated"),
      "params": { "tokenUsage": usage, .. },
      ..
    } => self.capture_token_usage(usage)
    {
      "method": String("turn/completed"),
      "params": {
        "turn": { "status": String("failed"), "error": String(message), .. },
        ..
      },
      ..
    } => {
      self.close_current_message(events)
      events.push(("response.completed", self.build_failed_event(message)))
    }
    {
      "method": String("turn/completed"),
      "params": { "turn": { "status": String("failed"), .. }, .. },
      ..
    } => {
      self.close_current_message(events)
      events.push(
        (
          "response.completed",
          self.build_failed_event("Codex turn completed with failed status"),
        ),
      )
    }
    { "method": String("turn/completed"), .. } => {
      self.close_current_message(events)
      events.push(("response.completed", self.build_completed_event()))
    }
    {
      "method": String("error"),
      "params": { "message": String(message), .. },
      ..
    } => {
      self.close_current_message(events)
      events.push(("response.completed", self.build_failed_event(message)))
    }
    { "method": String(rpc_method), .. } =>
      if is_documented_codex_stream_noop(rpc_method) {
        ()
      } else {
        abort("Unsupported Codex streaming event: " + event.data.stringify())
      }
    _ => abort("Malformed Codex streaming event: " + event.data.stringify())
  }
  events
}

///|
pub fn non_streaming_to_synthetic_events(json : Json) -> Array[@sse.SseEvent] {
  match json {
    Array(events) => events.map(fn(event) { { event: "message", data: event } })
    _ => []
  }
}

///|
fn CodexToResponsesTranslator::emit_lifecycle(
  self : CodexToResponsesTranslator,
  events : Array[(String, Json)],
) -> Unit {
  if not(self.has_emitted_created) {
    events.push(
      (
        "response.created",
        { "type": "response.created", "response": { "id": self.response_id } },
      ),
    )
    self.has_emitted_created = true
  }
  if not(self.has_emitted_in_progress) {
    events.push(
      (
        "response.in_progress",
        {
          "type": "response.in_progress",
          "response": { "id": self.response_id, "status": "in_progress" },
        },
      ),
    )
    self.has_emitted_in_progress = true
  }
}

///|
fn CodexToResponsesTranslator::ensure_message_started(
  self : CodexToResponsesTranslator,
  events : Array[(String, Json)],
) -> Unit {
  if not(self.has_open_message) {
    let output_index = self.next_output_index
    self.next_output_index = self.next_output_index + 1
    let item_id = "msg_" + self.response_id + "_" + output_index.to_string()
    self.current_message_output_index = output_index
    self.current_message_item_id = item_id
    self.current_message_text = ""
    self.has_open_message = true
    events.push(
      (
        "response.output_item.added",
        {
          "type": "response.output_item.added",
          "output_index": output_index,
          "item": {
            "id": item_id,
            "type": "message",
            "status": "in_progress",
            "content": [],
            "role": "assistant",
          },
        },
      ),
    )
    events.push(
      (
        "response.content_part.added",
        {
          "type": "response.content_part.added",
          "content_index": 0,
          "item_id": item_id,
          "output_index": output_index,
          "part": { "type": "output_text", "annotations": [], "text": "" },
        },
      ),
    )
  }
}

///|
fn CodexToResponsesTranslator::emit_fallback_text(
  self : CodexToResponsesTranslator,
  events : Array[(String, Json)],
  text : String,
) -> Unit {
  if text.length() == 0 || self.current_message_text.length() > 0 {
    return
  }
  self.ensure_message_started(events)
  self.current_message_text = text
  events.push(
    (
      "response.output_text.delta",
      {
        "type": "response.output_text.delta",
        "delta": text,
        "content_index": 0,
        "item_id": self.current_message_item_id,
        "output_index": self.current_message_output_index,
      },
    ),
  )
}

///|
fn CodexToResponsesTranslator::close_current_message(
  self : CodexToResponsesTranslator,
  events : Array[(String, Json)],
) -> Unit {
  if not(self.has_open_message) {
    return
  }
  let text = self.current_message_text
  events.push(
    (
      "response.output_text.done",
      {
        "type": "response.output_text.done",
        "text": text,
        "content_index": 0,
        "item_id": self.current_message_item_id,
        "output_index": self.current_message_output_index,
      },
    ),
  )
  events.push(
    (
      "response.content_part.done",
      {
        "type": "response.content_part.done",
        "content_index": 0,
        "item_id": self.current_message_item_id,
        "output_index": self.current_message_output_index,
        "part": { "type": "output_text", "annotations": [], "text": text },
      },
    ),
  )
  let message_item : Json = {
    "id": self.current_message_item_id,
    "type": "message",
    "status": "completed",
    "role": "assistant",
    "content": [{ "type": "output_text", "text": text, "annotations": [] }],
  }
  events.push(
    (
      "response.output_item.done",
      {
        "type": "response.output_item.done",
        "output_index": self.current_message_output_index,
        "item": message_item,
      },
    ),
  )
  self.completed_output.push(message_item)
  self.has_open_message = false
  self.current_message_output_index = -1
  self.current_message_item_id = ""
  self.current_message_text = ""
}

///|
fn CodexToResponsesTranslator::capture_token_usage(
  self : CodexToResponsesTranslator,
  token_usage : Json,
) -> Unit {
  match CodexTokenUsage::from_json(token_usage) {
    Some(usage) => {
      self.input_tokens = usage.input_tokens
      self.output_tokens = usage.output_tokens
      self.total_tokens = usage.total_tokens
    }
    None => ()
  }
}

///|
fn CodexToResponsesTranslator::build_completed_event(
  self : CodexToResponsesTranslator,
) -> Json {
  let response : Map[String, Json] = {
    "id": Json::string(self.response_id),
    "status": Json::string("completed"),
    "output": Json::array(self.completed_output.copy()),
  }
  if self.model.length() > 0 {
    response["model"] = Json::string(self.model)
  }
  if self.total_tokens > 0 {
    response["usage"] = {
      "input_tokens": self.input_tokens,
      "output_tokens": self.output_tokens,
      "total_tokens": self.total_tokens,
    }
  }
  { "type": "response.completed", "response": Json::object(response) }
}

///|
fn CodexToResponsesTranslator::build_failed_event(
  self : CodexToResponsesTranslator,
  message : String,
) -> Json {
  let response : Map[String, Json] = {
    "id": Json::string(self.response_id),
    "status": Json::string("failed"),
    "output": Json::array(self.completed_output.copy()),
    "error": { "type": "api_error", "message": message },
  }
  if self.model.length() > 0 {
    response["model"] = Json::string(self.model)
  }
  { "type": "response.completed", "response": Json::object(response) }
}

///|
fn is_documented_codex_stream_noop(rpc_method : String) -> Bool {
  match rpc_method {
    "thread/started"
    | "turn/started"
    | "item/started"
    | "thread/tokenUsage/updated"
    | "codex/event/agent_message_content_delta"
    | "codex/event/token_count"
    | "codex/event/session_configured"
    | "codex/event/task_started" => true
    _ => false
  }
}
