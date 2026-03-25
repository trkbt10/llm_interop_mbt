///|
/// Anthropic SSE to Responses API SSE translator
///
/// Translates Anthropic Messages API streaming events to OpenAI Responses API events.
/// Flow: Anthropic SSE events -> Responses API SSE events

///|
/// Anthropic SSE to Responses API event translator
/// Accumulative: holds state while generating translation events
struct AnthropicToResponsesTranslator {
  response_id : String
  mut output_index : Int
  mut has_emitted_created : Bool
  mut current_tool_call_id : String
  mut current_tool_mode : String
  mut current_block_type : String
  tool_input_buffer : StringBuilder
  text_buffer : StringBuilder
  current_text_block : StringBuilder
  mut current_text_citations : Array[Json]
  thinking_buffer : StringBuilder
  redacted_thinking_buffer : StringBuilder
  mut in_thinking_block : Bool
  mut in_redacted_thinking_block : Bool
}

///|
/// Creates a new translator with the given response ID
pub fn AnthropicToResponsesTranslator::new(
  response_id~ : String,
) -> AnthropicToResponsesTranslator {
  {
    response_id,
    output_index: 0,
    has_emitted_created: false,
    current_tool_call_id: "",
    current_tool_mode: "",
    current_block_type: "",
    tool_input_buffer: StringBuilder::new(),
    text_buffer: StringBuilder::new(),
    current_text_block: StringBuilder::new(),
    current_text_citations: [],
    thinking_buffer: StringBuilder::new(),
    redacted_thinking_buffer: StringBuilder::new(),
    in_thinking_block: false,
    in_redacted_thinking_block: false,
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
          self.current_block_type = "tool_use"
          // Convert Claude tool use ID to Responses API format
          let call_id = @interop_util.anthropic_to_openai_responses_call_id(id)
          self.current_tool_call_id = call_id
          self.current_tool_mode = "function"
          self.tool_input_buffer.reset()
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
        {
          "content_block": {
            "type": String("server_tool_use"),
            "id": String(id),
            "name": String(name),
            ..
          },
          ..
        } => {
          self.current_block_type = "server_tool_use"
          let call_id = @interop_util.anthropic_to_openai_responses_call_id(id)
          self.current_tool_call_id = call_id
          self.tool_input_buffer.reset()
          self.output_index = self.output_index + 1
          if name == @types.web_search_tool_name() {
            self.current_tool_mode = "web_search"
            events.push(
              (
                "response.output_item.added",
                {
                  "type": "response.output_item.added",
                  "output_index": self.output_index,
                  "item": {
                    "type": "web_search_call",
                    "id": call_id,
                    "status": "in_progress",
                    "action": { "type": "search" },
                  },
                },
              ),
            )
            events.push(
              (
                "response.web_search_call.in_progress",
                {
                  "type": "response.web_search_call.in_progress",
                  "item_id": call_id,
                  "output_index": self.output_index,
                },
              ),
            )
          } else {
            self.current_tool_mode = "server_tool"
          }
        }
        { "content_block": { "type": String(type_), .. }, .. } =>
          if is_anthropic_content_block_start_noop_type(type_) {
            self.current_block_type = type_
            if type_ == "text" {
              self.current_text_block.reset()
              self.current_text_citations = []
            }
            ()
          } else {
            abort(
              "Unsupported Anthropic content_block_start type: " +
              event.data.stringify(),
            )
          }
        _ =>
          abort(
            "Anthropic content_block_start event is missing content_block.type: " +
            event.data.stringify(),
          )
      }
    "content_block_delta" =>
      match event.data {
        {
          "delta": { "type": String("text_delta"), "text": String(text), .. },
          ..
        } => {
          self.text_buffer.write_string(text)
          self.current_text_block.write_string(text)
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
            self.tool_input_buffer.write_string(partial)
            if self.current_tool_mode == "function" {
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
          }
        // Ref: docs/upstream/anthropic-messages-api.md:3971-3979 — ThinkingBlock
        // Accumulate thinking_delta; emit single reasoning item on content_block_stop
        {
          "delta": {
            "type": String("thinking_delta"),
            "thinking": String(text),
            ..
          },
          ..
        } => {
          self.thinking_buffer.write_string(text)
          self.in_thinking_block = true
        }
        {
          "delta": {
            "type": String("redacted_thinking_delta"),
            "data": String(data),
            ..
          },
          ..
        } => {
          self.redacted_thinking_buffer.write_string(data)
          self.in_redacted_thinking_block = true
        }
        {
          "delta": {
            "type": String("citations_delta"),
            "citation": citation,
            ..
          },
          ..
        } =>
          if self.current_block_type == "text" {
            self.current_text_citations.push(citation)
          } else {
            abort(
              "Anthropic citations_delta arrived outside an active text block: " +
              event.data.stringify(),
            )
          }
        // Ref: docs/upstream/anthropic-code-execution-tool.md:1796-1802 — code_execution_result
        {
          "delta": {
            "type": String("code_execution_result_delta"),
            "content": content_obj,
            ..
          },
          ..
        } => {
          let output = normalize_code_execution_result(content_obj).to_output_text()
          self.text_buffer.write_string(output)
          events.push(
            (
              "response.output_text.delta",
              {
                "type": "response.output_text.delta",
                "delta": output,
                "output_index": self.output_index,
              },
            ),
          )
        }
        { "delta": { "type": String(type_), .. }, .. } =>
          if is_anthropic_content_block_delta_noop_type(type_) {
            ()
          } else {
            abort(
              "Unsupported Anthropic content_block_delta type: " +
              event.data.stringify(),
            )
          }
        _ =>
          abort(
            "Anthropic content_block_delta event is missing delta.type: " +
            event.data.stringify(),
          )
      }
    "content_block_stop" => {
      if self.current_block_type == "text" {
        self.emit_text_annotation_events(events)
      }
      if self.in_thinking_block {
        // Emit accumulated thinking as a single reasoning item
        let thinking_text = self.thinking_buffer.to_string()
        if thinking_text.length() > 0 {
          events.push(
            (
              "response.output_item.done",
              {
                "type": "response.output_item.done",
                "output_index": self.output_index,
                "item": {
                  "type": "reasoning",
                  "summary": Json::array([
                    { "type": "summary_text", "text": thinking_text },
                  ]),
                },
              },
            ),
          )
        }
        self.thinking_buffer.reset()
        self.in_thinking_block = false
      } else if self.in_redacted_thinking_block {
        let encrypted = self.redacted_thinking_buffer.to_string()
        if encrypted.length() > 0 {
          events.push(
            (
              "response.output_item.done",
              {
                "type": "response.output_item.done",
                "output_index": self.output_index,
                "item": {
                  "type": "reasoning",
                  "summary": Json::array([]),
                  "encrypted_content": encrypted,
                },
              },
            ),
          )
        }
        self.redacted_thinking_buffer.reset()
        self.in_redacted_thinking_block = false
      } else if self.current_tool_call_id.length() > 0 {
        if self.current_tool_mode == "web_search" {
          let raw_input = self.tool_input_buffer.to_string()
          let input : Json = @json.parse(raw_input) catch {
            _ =>
              abort(
                "Anthropic web_search tool input must be valid JSON: " +
                raw_input,
              )
          }
          events.push(
            (
              "response.web_search_call.completed",
              {
                "type": "response.web_search_call.completed",
                "item_id": self.current_tool_call_id,
                "output_index": self.output_index,
              },
            ),
          )
          events.push(
            (
              "response.output_item.done",
              {
                "type": "response.output_item.done",
                "output_index": self.output_index,
                "item": {
                  "type": "web_search_call",
                  "id": self.current_tool_call_id,
                  "status": "completed",
                  "action": @types.build_web_search_action(input),
                },
              },
            ),
          )
        } else if self.current_tool_mode == "function" {
          // Tool call completed
          events.push(
            (
              "response.output_item.done",
              {
                "type": "response.output_item.done",
                "output_index": self.output_index,
              },
            ),
          )
        }
        self.current_tool_call_id = ""
        self.current_tool_mode = ""
        self.tool_input_buffer.reset()
      }
      self.current_block_type = ""
    }
    "message_delta" =>
      match event.data {
        { "delta": { "stop_reason": String(stop_reason), .. }, .. } =>
          if stop_reason == "end_turn" ||
            stop_reason == "stop" ||
            stop_reason == "pause_turn" {
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
        { "delta": Object(_), .. } => ()
        _ =>
          abort(
            "Anthropic message_delta event is missing delta object: " +
            event.data.stringify(),
          )
      }
    "message_stop" =>
      events.push(("response.completed", { "type": "response.completed" }))
    "message_start" | "ping" => ()
    _ =>
      abort(
        "Unsupported Anthropic SSE event type: " +
        event.event +
        " " +
        event.data.stringify(),
      )
  }
  events
}

///|
fn is_anthropic_content_block_start_noop_type(type_ : String) -> Bool {
  [
    "text", "thinking", "redacted_thinking", "code_execution_tool_result", "bash_code_execution_tool_result",
    "text_editor_code_execution_tool_result", "web_search_tool_result", "web_fetch_tool_result",
  ].contains(type_)
}

///|
fn is_anthropic_content_block_delta_noop_type(type_ : String) -> Bool {
  // Ref: docs/upstream/anthropic-messages-api.md:17820-18022
  // signature_delta is documented metadata without a Responses carrier here.
  // citations_delta is preserved above as interop annotations.
  ["signature_delta"].contains(type_)
}

///|
/// Get accumulated text (for debugging/logging)
pub fn AnthropicToResponsesTranslator::get_text(
  self : AnthropicToResponsesTranslator,
) -> String {
  self.text_buffer.to_string()
}

///|
fn AnthropicToResponsesTranslator::emit_text_annotation_events(
  self : AnthropicToResponsesTranslator,
  events : Array[(String, Json)],
) -> Unit {
  let block_text = self.current_text_block.to_string()
  let end_index = self.text_buffer.to_string().length()
  let start_index = end_index - block_text.length()
  let annotations : Array[@types.ResponseAnnotation] = []
  append_anthropic_citations(
    annotations,
    self.current_text_citations,
    start_index,
    end_index,
  )
  for annotation in annotations {
    events.push(
      (
        "response.output_text.annotation.added",
        {
          "type": "response.output_text.annotation.added",
          "annotation": annotation.to_interop_json(),
          "output_index": self.output_index,
        },
      ),
    )
  }
  self.current_text_block.reset()
  self.current_text_citations = []
}
