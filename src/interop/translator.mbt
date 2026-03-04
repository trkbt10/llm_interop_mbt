///|
/// Harmony SSE to Responses API SSE translator

///|
/// Harmony Chat Completions SSE chunk to Responses API event format translator
/// Accumulative: holds state while generating translation events
pub struct HarmonyToResponsesTranslator {
  response_id : String
  mut output_index : Int
  mut has_emitted_created : Bool
  mut current_tool_call_id : String
  text_buffer : StringBuilder
  reasoning_buffer : StringBuilder
}

///|
pub fn HarmonyToResponsesTranslator::new(
  response_id~ : String,
) -> HarmonyToResponsesTranslator {
  {
    response_id,
    output_index: 0,
    has_emitted_created: false,
    current_tool_call_id: "",
    text_buffer: StringBuilder::new(),
    reasoning_buffer: StringBuilder::new(),
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
  // Emit response.created on first event
  if not(self.has_emitted_created) {
    events.push(
      (
        "response.created",
        { "type": "response.created", "response": { "id": self.response_id } },
      ),
    )
    self.has_emitted_created = true
  }
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
                  self.text_buffer.write_string(content)
                  events.push(
                    (
                      "response.output_text.delta",
                      {
                        "type": "response.output_text.delta",
                        "delta": content,
                        "output_index": self.output_index,
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
                for tc in tc_deltas {
                  let tc_events = self.translate_tool_call(tc)
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
            events.push(
              (
                "response.output_text.done",
                {
                  "type": "response.output_text.done",
                  "text": self.text_buffer.to_string(),
                  "output_index": self.output_index,
                },
              ),
            )
            events.push(
              ("response.completed", { "type": "response.completed" }),
            )
          }
          { "finish_reason": String("tool_calls"), .. } =>
            events.push(
              ("response.completed", { "type": "response.completed" }),
            )
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
  match tc {
    // New tool call with id and name
    { "id": String(id), "function": { "name": String(name), .. }, .. } => {
      self.current_tool_call_id = id
      self.output_index = self.output_index + 1
      events.push(
        (
          "response.output_item.added",
          {
            "type": "response.output_item.added",
            "output_index": self.output_index,
            "item": {
              "type": "function_call",
              "id": id,
              "call_id": id,
              "name": name,
              "arguments": "",
            },
          },
        ),
      )
      // If arguments are included in first chunk
      match tc {
        { "function": { "arguments": String(args), .. }, .. } =>
          if args.length() > 0 {
            events.push(
              (
                "response.function_call_arguments.delta",
                {
                  "type": "response.function_call_arguments.delta",
                  "delta": args,
                  "output_index": self.output_index,
                },
              ),
            )
          }
        _ => ()
      }
    }
    // Arguments delta for existing tool call
    { "function": { "arguments": String(args), .. }, .. } =>
      if args.length() > 0 {
        events.push(
          (
            "response.function_call_arguments.delta",
            {
              "type": "response.function_call_arguments.delta",
              "delta": args,
              "output_index": self.output_index,
            },
          ),
        )
      }
    _ => ()
  }
  events
}

///|
/// Get accumulated reasoning (for debugging/logging)
pub fn HarmonyToResponsesTranslator::get_reasoning(
  self : HarmonyToResponsesTranslator,
) -> String {
  self.reasoning_buffer.to_string()
}
