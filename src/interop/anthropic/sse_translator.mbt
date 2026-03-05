///|
/// Anthropic SSE to Responses API SSE translator
///
/// Translates Anthropic Messages API streaming events to OpenAI Responses API events.
/// Flow: Anthropic SSE events -> Responses API SSE events

///|
/// Anthropic SSE to Responses API event translator
/// Accumulative: holds state while generating translation events
pub struct AnthropicToResponsesTranslator {
  response_id : String
  mut output_index : Int
  mut has_emitted_created : Bool
  mut current_tool_call_id : String
  mut current_tool_name : String
  text_buffer : StringBuilder
}

///|
pub fn AnthropicToResponsesTranslator::new(
  response_id~ : String,
) -> AnthropicToResponsesTranslator {
  {
    response_id,
    output_index: 0,
    has_emitted_created: false,
    current_tool_call_id: "",
    current_tool_name: "",
    text_buffer: StringBuilder::new(),
  }
}

///|
/// Process Anthropic SSE event and generate Responses API events
/// Returns: Array of generated Responses API events (event_type, data)
pub fn AnthropicToResponsesTranslator::translate(
  self : AnthropicToResponsesTranslator,
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
  // Process based on Anthropic event type
  match event.event {
    "content_block_start" =>
      match event.data {
        {
          "content_block": {
            "type": String("tool_use"),
            "id": String(id),
            "name": String(name),
            ..
          },
          ..
        } => {
          // Convert Claude tool use ID to Responses API format
          let call_id = @interop_util.anthropic_to_openai_responses_call_id(id)
          self.current_tool_call_id = call_id
          self.current_tool_name = name
          self.output_index = self.output_index + 1
          events.push(
            (
              "response.output_item.added",
              {
                "type": "response.output_item.added",
                "output_index": self.output_index,
                "item": {
                  "type": "function_call",
                  "id": call_id,
                  "call_id": call_id,
                  "name": name,
                  "arguments": "",
                },
              },
            ),
          )
        }
        _ => ()
      }
    "content_block_delta" =>
      match event.data {
        {
          "delta": { "type": String("text_delta"), "text": String(text), .. },
          ..
        } => {
          self.text_buffer.write_string(text)
          events.push(
            (
              "response.output_text.delta",
              {
                "type": "response.output_text.delta",
                "delta": text,
                "output_index": self.output_index,
              },
            ),
          )
        }
        {
          "delta": {
            "type": String("input_json_delta"),
            "partial_json": String(partial),
            ..
          },
          ..
        } =>
          if partial.length() > 0 {
            events.push(
              (
                "response.function_call_arguments.delta",
                {
                  "type": "response.function_call_arguments.delta",
                  "delta": partial,
                  "output_index": self.output_index,
                },
              ),
            )
          }
        _ => ()
      }
    "content_block_stop" =>
      // Tool call completed
      if self.current_tool_call_id.length() > 0 {
        events.push(
          (
            "response.output_item.done",
            {
              "type": "response.output_item.done",
              "output_index": self.output_index,
            },
          ),
        )
        self.current_tool_call_id = ""
        self.current_tool_name = ""
      }
    "message_delta" =>
      match event.data {
        { "delta": { "stop_reason": String(stop_reason), .. }, .. } =>
          if stop_reason == "end_turn" || stop_reason == "stop" {
            // Emit text done if we have accumulated text
            let text = self.text_buffer.to_string()
            if text.length() > 0 {
              events.push(
                (
                  "response.output_text.done",
                  {
                    "type": "response.output_text.done",
                    "text": text,
                    "output_index": 0,
                  },
                ),
              )
            }
          }
        _ => ()
      }
    "message_stop" =>
      events.push(("response.completed", { "type": "response.completed" }))
    _ => () // message_start, ping, etc.
  }
  events
}

///|
/// Get accumulated text (for debugging/logging)
pub fn AnthropicToResponsesTranslator::get_text(
  self : AnthropicToResponsesTranslator,
) -> String {
  self.text_buffer.to_string()
}
