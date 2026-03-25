///|
/// Gemini SSE to Responses API SSE translator
///
/// Translates Gemini streamGenerateContent SSE events to OpenAI Responses API events.
/// Flow: Gemini SSE events -> Responses API SSE events

///|
/// Gemini SSE to Responses API event translator
struct GeminiToResponsesTranslator {
  response_id : String
  model : String
  mut next_output_index : Int
  mut has_emitted_created : Bool
  mut has_emitted_in_progress : Bool
  mut has_open_message : Bool
  mut current_message_output_index : Int
  mut current_message_item_id : String
  mut current_message_text : String
  mut current_message_annotations : Array[@types.ResponseAnnotation]
  tool_calls : Array[GeminiToolCallState]
  completed_output : Array[Json]
}

///|
priv struct GeminiToolCallState {
  output_index : Int
  call_id : String
  name : String
  arguments : StringBuilder
  mut completed : Bool
}

///|
pub fn GeminiToResponsesTranslator::new(
  response_id~ : String,
  model? : String = "",
) -> GeminiToResponsesTranslator {
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
    current_message_annotations: [],
    tool_calls: [],
    completed_output: [],
  }
}

///|
/// Process Gemini SSE event and generate Responses API events
pub fn GeminiToResponsesTranslator::translate(
  self : GeminiToResponsesTranslator,
  event : @sse.SseEvent,
) -> Array[(String, Json)] {
  let events : Array[(String, Json)] = []
  self.emit_lifecycle(events)
  match parse_stream_chunk(event.data) {
    Some((text, calls)) => {
      // Text content
      if text.length() > 0 {
        self.ensure_message_started(events)
        self.current_message_text = self.current_message_text + text
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
      self.refresh_current_message_annotations(event.data)
      // Tool calls
      for call in calls {
        self.close_current_message(events)
        let output_index = self.next_output_index
        self.next_output_index = self.next_output_index + 1
        let args_str = call.arguments.stringify()
        let state : GeminiToolCallState = {
          output_index,
          call_id: call.id,
          name: call.name,
          arguments: StringBuilder::new(),
          completed: false,
        }
        state.arguments.write_string(args_str)
        self.tool_calls.push(state)
        events.push(
          (
            "response.output_item.added",
            {
              "type": "response.output_item.added",
              "output_index": output_index,
              "item": {
                "type": "function_call",
                "id": call.id,
                "call_id": call.id,
                "name": call.name,
                "arguments": "",
                "status": "in_progress",
              },
            },
          ),
        )
        events.push(
          (
            "response.function_call_arguments.delta",
            {
              "type": "response.function_call_arguments.delta",
              "delta": args_str,
              "item_id": call.id,
              "output_index": output_index,
            },
          ),
        )
      }
    }
    None => ()
  }
  self.refresh_current_message_annotations(event.data)
  // Check for finish
  // Ref: docs/upstream/gemini-generate-content.md:2948-2950
  //   STOP — Natural stop point of the model or provided stop sequence.
  //   MAX_TOKENS — The maximum number of tokens as specified in the request was reached.
  //   SAFETY — The response candidate content was flagged for safety reasons.
  match event.data {
    { "candidates": Array(candidates), .. } =>
      if candidates.length() > 0 {
        match candidates[0] {
          { "finishReason": String("STOP"), .. }
          | { "finishReason": String("MAX_TOKENS"), .. } => {
            self.close_current_message(events)
            self.close_tool_calls(events)
            events.push(("response.completed", self.build_completed_event()))
          }
          // SAFETY / RECITATION / OTHER: emit error-completed response
          { "finishReason": String(reason), .. } => {
            self.close_current_message(events)
            self.close_tool_calls(events)
            let response : Map[String, Json] = {}
            response["id"] = Json::string(self.response_id)
            response["status"] = Json::string("failed")
            response["output"] = Json::array(self.completed_output.copy())
            response["error"] = Json::object({
              "type": Json::string("content_filter"),
              "message": Json::string(
                "Response blocked: finishReason=\{reason}",
              ),
            })
            if self.model.length() > 0 {
              response["model"] = Json::string(self.model)
            }
            events.push(
              (
                "response.completed",
                {
                  "type": "response.completed",
                  "response": Json::object(response),
                },
              ),
            )
          }
          _ => ()
        }
      }
    _ => ()
  }
  events
}

///|
fn GeminiToResponsesTranslator::emit_lifecycle(
  self : GeminiToResponsesTranslator,
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
fn GeminiToResponsesTranslator::ensure_message_started(
  self : GeminiToResponsesTranslator,
  events : Array[(String, Json)],
) -> Unit {
  if not(self.has_open_message) {
    let output_index = self.next_output_index
    self.next_output_index = self.next_output_index + 1
    let item_id = "msg_" + self.response_id + "_" + output_index.to_string()
    self.current_message_output_index = output_index
    self.current_message_item_id = item_id
    self.current_message_text = ""
    self.current_message_annotations = []
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
          "part": { "type": "output_text", "text": "" },
        },
      ),
    )
  }
}

///|
fn GeminiToResponsesTranslator::close_current_message(
  self : GeminiToResponsesTranslator,
  events : Array[(String, Json)],
) -> Unit {
  if not(self.has_open_message) {
    return
  }
  let text = normalize_structured_output_text(self.current_message_text)
  let annotation_json : Array[Json] = []
  for annotation in self.current_message_annotations {
    events.push(
      (
        "response.output_text.annotation.added",
        {
          "type": "response.output_text.annotation.added",
          "annotation": annotation.to_interop_json(),
          "output_index": self.current_message_output_index,
        },
      ),
    )
    annotation_json.push(annotation.to_interop_json())
  }
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
  let message_item : Json = {
    "id": self.current_message_item_id,
    "type": "message",
    "status": "completed",
    "role": "assistant",
    "content": [
      {
        "type": "output_text",
        "text": text,
        "annotations": Json::array(annotation_json),
      },
    ],
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
  self.current_message_annotations = []
}

///|
fn GeminiToResponsesTranslator::refresh_current_message_annotations(
  self : GeminiToResponsesTranslator,
  chunk_json : Json,
) -> Unit {
  if not(self.has_open_message) || self.current_message_text.length() == 0 {
    return
  }
  match chunk_json {
    { "candidates": Array(candidates), .. } if candidates.length() > 0 => {
      let annotations = collect_gemini_grounding_annotations(
        candidates[0],
        self.current_message_text,
      )
      if annotations.length() > 0 {
        self.current_message_annotations = annotations
      }
    }
    _ => ()
  }
}

///|
fn GeminiToResponsesTranslator::close_tool_calls(
  self : GeminiToResponsesTranslator,
  events : Array[(String, Json)],
) -> Unit {
  for tc in self.tool_calls {
    if tc.completed {
      continue
    }
    let arguments = tc.arguments.to_string()
    events.push(
      (
        "response.function_call_arguments.done",
        {
          "type": "response.function_call_arguments.done",
          "arguments": arguments,
          "item_id": tc.call_id,
          "output_index": tc.output_index,
        },
      ),
    )
    let tc_item : Json = {
      "id": tc.call_id,
      "type": "function_call",
      "status": "completed",
      "arguments": arguments,
      "call_id": tc.call_id,
      "name": tc.name,
    }
    events.push(
      (
        "response.output_item.done",
        {
          "type": "response.output_item.done",
          "output_index": tc.output_index,
          "item": tc_item,
        },
      ),
    )
    self.completed_output.push(tc_item)
    tc.completed = true
  }
}

///|
fn GeminiToResponsesTranslator::build_completed_event(
  self : GeminiToResponsesTranslator,
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
