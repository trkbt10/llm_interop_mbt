///|
/// Harmony SSE to Responses API SSE translator

///|
/// Harmony Chat Completions SSE chunk to Responses API event format translator
/// Accumulative: holds state while generating translation events
pub struct HarmonyToResponsesTranslator {
  response_id : String
  model : String
  mut next_output_index : Int
  mut has_emitted_created : Bool
  mut has_emitted_in_progress : Bool
  mut current_message_output_index : Int
  mut current_message_item_id : String
  mut current_message_text : String
  mut has_open_message : Bool
  tool_calls : Array[HarmonyToolCallState]
  reasoning_buffer : StringBuilder
  /// Accumulated completed output items for response.completed
  completed_output : Array[Json]
}

///|
struct HarmonyToolCallState {
  key : String
  output_index : Int
  mut call_id : String
  mut name : String
  arguments : StringBuilder
  mut completed : Bool
}

///|
/// Creates a new translator with the given response ID and optional model name
pub fn HarmonyToResponsesTranslator::new(
  response_id~ : String,
  model? : String = "",
) -> HarmonyToResponsesTranslator {
  {
    response_id,
    model,
    next_output_index: 0,
    has_emitted_created: false,
    has_emitted_in_progress: false,
    current_message_output_index: -1,
    current_message_item_id: "",
    current_message_text: "",
    has_open_message: false,
    tool_calls: [],
    reasoning_buffer: StringBuilder::new(),
    completed_output: [],
  }
}

///|
/// Process Harmony SSE event and generate Responses API events
/// Returns: Array of generated Responses API events (event_type, data)
pub fn HarmonyToResponsesTranslator::translate(
  self : HarmonyToResponsesTranslator,
  event : @sse.SseEvent,
) -> Array[(String, Json)] {
  let events : Array[(String, Json)] = []
  self.emit_response_lifecycle(events)
  match event.data {
    { "choices": Array(choices), .. } =>
      if choices.length() > 0 {
        let choice = choices[0]
        match choice {
          { "delta": delta, .. } => {
            // Text content delta -> response.output_text.delta
            match delta {
              { "content": String(content), .. } =>
                if content.length() > 0 {
                  self.close_open_tool_calls(events)
                  self.ensure_message_started(events)
                  self.current_message_text = self.current_message_text +
                    content
                  events.push(
                    (
                      "response.output_text.delta",
                      {
                        "type": "response.output_text.delta",
                        "delta": content,
                        "content_index": 0,
                        "item_id": self.current_message_item_id,
                        "output_index": self.current_message_output_index,
                      },
                    ),
                  )
                }
              _ => ()
            }
            // Reasoning delta (optional, for debugging/logging)
            match delta {
              { "reasoning": String(r), .. } =>
                self.reasoning_buffer.write_string(r)
              _ => ()
            }
            // Tool calls
            match delta {
              { "tool_calls": Array(tc_deltas), .. } =>
                for tc_delta in tc_deltas {
                  let tc_events = self.translate_tool_call(tc_delta)
                  for e in tc_events {
                    events.push(e)
                  }
                }
              _ => ()
            }
          }
          _ => ()
        }
        // Check finish_reason
        match choice {
          { "finish_reason": String("stop"), .. } => {
            self.close_open_tool_calls(events)
            self.close_current_message(events)
            events.push(("response.completed", self.build_completed_event()))
          }
          { "finish_reason": String("tool_calls"), .. } => {
            self.close_current_message(events)
            self.close_open_tool_calls(events)
            events.push(("response.completed", self.build_completed_event()))
          }
          _ => ()
        }
      }
    _ => ()
  }
  events
}

///|
fn HarmonyToResponsesTranslator::translate_tool_call(
  self : HarmonyToResponsesTranslator,
  tc : Json,
) -> Array[(String, Json)] {
  let events : Array[(String, Json)] = []
  self.close_current_message(events)
  let key = harmony_tool_call_key(tc)
  let state_index = self.find_tool_call_state(key, tc)
  if state_index < 0 {
    let output_index = self.next_output_index
    self.next_output_index = self.next_output_index + 1
    let call_id = harmony_tool_call_id(tc, self.response_id, output_index)
    let name = harmony_tool_call_name(tc)
    let state : HarmonyToolCallState = {
      key,
      output_index,
      call_id,
      name,
      arguments: StringBuilder::new(),
      completed: false,
    }
    self.tool_calls.push(state)
    events.push(
      (
        "response.output_item.added",
        {
          "type": "response.output_item.added",
          "output_index": output_index,
          "item": {
            "type": "function_call",
            "id": call_id,
            "call_id": call_id,
            "name": name,
            "arguments": "",
            "status": "in_progress",
          },
        },
      ),
    )
  }
  let resolved_index = self.find_tool_call_state(key, tc)
  if resolved_index >= 0 {
    match tc {
      { "id": String(id), .. } => self.tool_calls[resolved_index].call_id = id
      _ => ()
    }
    match tc {
      { "function": { "name": String(name), .. }, .. } =>
        self.tool_calls[resolved_index].name = name
      _ => ()
    }
    match tc {
      { "function": { "arguments": String(args), .. }, .. } =>
        if args.length() > 0 {
          self.tool_calls[resolved_index].arguments.write_string(args)
          events.push(
            (
              "response.function_call_arguments.delta",
              {
                "type": "response.function_call_arguments.delta",
                "delta": args,
                "item_id": self.tool_calls[resolved_index].call_id,
                "output_index": self.tool_calls[resolved_index].output_index,
              },
            ),
          )
        }
      _ => ()
    }
  }
  events
}

///|
fn HarmonyToResponsesTranslator::emit_response_lifecycle(
  self : HarmonyToResponsesTranslator,
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
fn HarmonyToResponsesTranslator::ensure_message_started(
  self : HarmonyToResponsesTranslator,
  events : Array[(String, Json)],
) -> Unit {
  if not(self.has_open_message) {
    let output_index = self.next_output_index
    self.next_output_index = self.next_output_index + 1
    let item_id = self.make_message_item_id(output_index)
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
          "part": {
            "type": "output_text",
            "annotations": [],
            "logprobs": [],
            "text": "",
          },
        },
      ),
    )
  }
}

///|
fn HarmonyToResponsesTranslator::close_current_message(
  self : HarmonyToResponsesTranslator,
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
        "part": {
          "type": "output_text",
          "annotations": [],
          "logprobs": [],
          "text": text,
        },
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
  self.current_message_output_index = -1
  self.current_message_item_id = ""
  self.current_message_text = ""
  self.has_open_message = false
}

///|
fn HarmonyToResponsesTranslator::close_open_tool_calls(
  self : HarmonyToResponsesTranslator,
  events : Array[(String, Json)],
) -> Unit {
  for i in 0..<self.tool_calls.length() {
    if self.tool_calls[i].completed {
      continue
    }
    let arguments = self.tool_calls[i].arguments.to_string()
    events.push(
      (
        "response.function_call_arguments.done",
        {
          "type": "response.function_call_arguments.done",
          "arguments": arguments,
          "item_id": self.tool_calls[i].call_id,
          "output_index": self.tool_calls[i].output_index,
        },
      ),
    )
    let tc_item : Json = {
      "id": self.tool_calls[i].call_id,
      "type": "function_call",
      "status": "completed",
      "arguments": arguments,
      "call_id": self.tool_calls[i].call_id,
      "name": self.tool_calls[i].name,
    }
    events.push(
      (
        "response.output_item.done",
        {
          "type": "response.output_item.done",
          "output_index": self.tool_calls[i].output_index,
          "item": tc_item,
        },
      ),
    )
    self.completed_output.push(tc_item)
    self.tool_calls[i].completed = true
  }
}

///|
fn HarmonyToResponsesTranslator::find_tool_call_state(
  self : HarmonyToResponsesTranslator,
  key : String,
  tc : Json,
) -> Int {
  if key.length() > 0 {
    for i in 0..<self.tool_calls.length() {
      if self.tool_calls[i].key == key {
        return i
      }
    }
  }
  match tc {
    { "id": String(id), .. } =>
      for i in 0..<self.tool_calls.length() {
        if self.tool_calls[i].call_id == id {
          return i
        }
      }
    _ => ()
  }
  -1
}

///|
fn HarmonyToResponsesTranslator::make_message_item_id(
  self : HarmonyToResponsesTranslator,
  output_index : Int,
) -> String {
  "msg_" + self.response_id + "_" + output_index.to_string()
}

///|
fn harmony_tool_call_key(tc : Json) -> String {
  match tc {
    { "index": Number(n, ..), .. } => "index:" + n.to_int().to_string()
    { "id": String(id), .. } => "id:" + id
    _ => ""
  }
}

///|
fn harmony_tool_call_id(
  tc : Json,
  response_id : String,
  output_index : Int,
) -> String {
  match tc {
    { "id": String(id), .. } => id
    _ => @interop_util.ToolCallIdProvider::OpenAIResponsesApi.prefix() + response_id + "_" + output_index.to_string()
  }
}

///|
fn harmony_tool_call_name(tc : Json) -> String {
  match tc {
    { "function": { "name": String(name), .. }, .. } => name
    _ => ""
  }
}

///|
fn HarmonyToResponsesTranslator::build_completed_event(
  self : HarmonyToResponsesTranslator,
) -> Json {
  let response : Map[String, Json] = {}
  response["id"] = Json::string(self.response_id)
  response["status"] = Json::string("completed")
  response["output"] = Json::array(self.completed_output.copy())
  if self.model.length() > 0 {
    response["model"] = Json::string(self.model)
  }
  { "type": "response.completed", "response": Json::object(response) }
}

///|
/// Get accumulated reasoning (for debugging/logging)
pub fn HarmonyToResponsesTranslator::get_reasoning(
  self : HarmonyToResponsesTranslator,
) -> String {
  self.reasoning_buffer.to_string()
}
