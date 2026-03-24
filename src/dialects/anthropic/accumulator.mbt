///|
/// Anthropic Messages API stream accumulator

///|
/// Anthropic Messages API stream accumulator
/// Accumulates content_block_delta (text_delta / input_json_delta)
pub struct AnthropicMessagesAccumulator {
  text : StringBuilder
  tool_calls : Array[@types.ToolCallAcc]
  mut stop_reason : String
  current_text : StringBuilder
  content_parts : Array[@types.ResponseContentPart]
  annotations : Array[@types.ResponseAnnotation]
  tool_traces : Array[@types.ToolCallTrace]
  mut current_block_type : String
  current_thinking : StringBuilder
  current_redacted_thinking : StringBuilder
  mut current_server_tool_id : String
  mut current_server_tool_name : String
  current_server_tool_input : StringBuilder
  mut current_text_citations : Array[Json]
}

///|
/// Creates a new empty accumulator
pub fn AnthropicMessagesAccumulator::new() -> AnthropicMessagesAccumulator {
  {
    text: StringBuilder::new(),
    tool_calls: [],
    stop_reason: "",
    current_text: StringBuilder::new(),
    content_parts: [],
    annotations: [],
    tool_traces: [],
    current_block_type: "",
    current_thinking: StringBuilder::new(),
    current_redacted_thinking: StringBuilder::new(),
    current_server_tool_id: "",
    current_server_tool_name: "",
    current_server_tool_input: StringBuilder::new(),
    current_text_citations: [],
  }
}

///|
/// Process SSE event
pub fn AnthropicMessagesAccumulator::feed(
  self : AnthropicMessagesAccumulator,
  event : @sse.SseEvent,
) -> Unit {
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
          self.flush_text_block()
          self.current_block_type = "tool_use"
          self.tool_calls.push(@types.ToolCallAcc::{
            id,
            name,
            arguments: StringBuilder::new(),
          })
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
          self.flush_text_block()
          self.current_block_type = "server_tool_use"
          self.current_server_tool_id = id
          self.current_server_tool_name = name
          self.current_server_tool_input.reset()
        }
        {
          "content_block": {
            "type": String("web_search_tool_result"),
            "tool_use_id": String(tool_use_id),
            ..
          },
          ..
        } => {
          self.flush_text_block()
          upsert_tool_trace(
            self.tool_traces,
            @interop_util.anthropic_to_openai_responses_call_id(tool_use_id),
            @types.web_search_tool_name(),
            @types.ToolCallKind::WebSearch,
            @types.ToolCallStatus::Completed,
            Json::object({}),
          )
          self.current_block_type = ""
        }
        {
          "content_block": {
            "type": String("web_fetch_tool_result"),
            "tool_use_id": String(tool_use_id),
            ..
          },
          ..
        } => {
          self.flush_text_block()
          upsert_tool_trace(
            self.tool_traces,
            @interop_util.anthropic_to_openai_responses_call_id(tool_use_id),
            "web_fetch",
            @types.ToolCallKind::Builtin(builtin_type="web_fetch"),
            @types.ToolCallStatus::Completed,
            Json::object({}),
          )
          self.current_block_type = ""
        }
        { "content_block": { "type": String(type_), .. }, .. } =>
          if is_anthropic_accumulator_content_block_start_type(type_) {
            if type_ != "text" {
              self.flush_text_block()
            }
            self.current_block_type = type_
            match type_ {
              "thinking" => self.current_thinking.reset()
              "redacted_thinking" => self.current_redacted_thinking.reset()
              "code_execution_tool_result"
              | "bash_code_execution_tool_result"
              | "text_editor_code_execution_tool_result" => ()
              "text" => self.current_text_citations = []
              _ => ()
            }
          } else {
            abort(
              "Unsupported Anthropic accumulator content_block_start type: " +
              event.data.stringify(),
            )
          }
        _ =>
          abort(
            "Anthropic accumulator content_block_start event is missing content_block.type: " +
            event.data.stringify(),
          )
      }
    "content_block_delta" =>
      match event.data {
        { "delta": { "type": String("text_delta"), "text": String(t), .. }, .. } =>
          self.current_text.write_string(t)
        {
          "delta": {
            "type": String("input_json_delta"),
            "partial_json": String(pj),
            ..
          },
          ..
        } =>
          if self.current_block_type == "server_tool_use" &&
            self.current_server_tool_id.length() > 0 {
            self.current_server_tool_input.write_string(pj)
          } else if self.tool_calls.length() > 0 {
            self.tool_calls[self.tool_calls.length() - 1].arguments.write_string(
              pj,
            )
          } else {
            abort(
              "Anthropic input_json_delta arrived without an active tool block: " +
              event.data.stringify(),
            )
          }
        {
          "delta": {
            "type": String("thinking_delta"),
            "thinking": String(thinking),
            ..
          },
          ..
        } => self.current_thinking.write_string(thinking)
        {
          "delta": {
            "type": String("redacted_thinking_delta"),
            "data": String(data),
            ..
          },
          ..
        } => self.current_redacted_thinking.write_string(data)
        {
          "delta": {
            "type": String("code_execution_result_delta"),
            "content": content_obj,
            ..
          },
          ..
        } => {
          self.flush_text_block()
          self.content_parts.push(build_code_execution_result_part(content_obj))
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
        { "delta": { "type": String(type_), .. }, .. } =>
          if is_anthropic_accumulator_content_block_delta_noop_type(type_) {
            ()
          } else {
            abort(
              "Unsupported Anthropic accumulator content_block_delta type: " +
              event.data.stringify(),
            )
          }
        _ =>
          abort(
            "Anthropic accumulator content_block_delta event is missing delta.type: " +
            event.data.stringify(),
          )
      }
    "message_delta" =>
      match event.data {
        { "delta": { "stop_reason": String(sr), .. }, .. } =>
          self.stop_reason = sr
        { "delta": Object(_), .. } => ()
        _ =>
          abort(
            "Anthropic accumulator message_delta event is missing delta object: " +
            event.data.stringify(),
          )
      }
    "content_block_stop" => self.finish_current_block()
    "message_start" | "ping" | "message_stop" => ()
    _ =>
      abort(
        "Unsupported Anthropic accumulator SSE event type: " +
        event.event +
        " " +
        event.data.stringify(),
      )
  }
}

///|
fn is_anthropic_accumulator_content_block_start_type(type_ : String) -> Bool {
  [
    "text", "thinking", "redacted_thinking", "server_tool_use", "code_execution_tool_result",
    "bash_code_execution_tool_result", "text_editor_code_execution_tool_result",
    "web_search_tool_result", "web_fetch_tool_result",
  ].contains(type_)
}

///|
fn is_anthropic_accumulator_content_block_delta_noop_type(
  type_ : String,
) -> Bool {
  // Ref: docs/upstream/anthropic-messages-api.md:17820-18022
  // signature_delta is documented metadata with no provider-neutral carrier in
  // the native ModelResponse surface here. citations_delta is handled above.
  ["signature_delta"].contains(type_)
}

///|
fn AnthropicMessagesAccumulator::flush_text_block(
  self : AnthropicMessagesAccumulator,
) -> Unit {
  let block = self.current_text.to_string()
  if block.length() > 0 {
    if self.text.to_string().length() > 0 {
      self.text.write_char('\n')
    }
    self.text.write_string(block)
    self.content_parts.push(@types.ResponseContentPart::OutputText(block))
    self.current_text.reset()
  }
}

///|
fn AnthropicMessagesAccumulator::finish_current_block(
  self : AnthropicMessagesAccumulator,
) -> Unit {
  match self.current_block_type {
    "text" => {
      let block = self.current_text.to_string()
      append_anthropic_citations(
        self.annotations,
        self.current_text_citations,
        anthropic_accumulator_output_text_length(self.content_parts),
        anthropic_accumulator_output_text_length(self.content_parts) +
        block.length(),
      )
      self.current_text_citations = []
      self.flush_text_block()
    }
    "thinking" => {
      self.flush_text_block()
      let thinking = self.current_thinking.to_string()
      if thinking.length() > 0 {
        self.content_parts.push(
          @types.ResponseContentPart::Thinking(text=thinking),
        )
      }
      self.current_thinking.reset()
    }
    "redacted_thinking" => {
      self.flush_text_block()
      let data = self.current_redacted_thinking.to_string()
      if data.length() > 0 {
        self.content_parts.push(
          @types.ResponseContentPart::RedactedThinking(data~),
        )
      }
      self.current_redacted_thinking.reset()
    }
    "server_tool_use" => {
      self.flush_text_block()
      let input = self.parse_current_server_tool_input()
      let trace_id = @interop_util.anthropic_to_openai_responses_call_id(
        self.current_server_tool_id,
      )
      match self.current_server_tool_name {
        "web_search" =>
          upsert_tool_trace(
            self.tool_traces,
            trace_id,
            @types.web_search_tool_name(),
            @types.ToolCallKind::WebSearch,
            @types.ToolCallStatus::InProgress,
            input,
          )
        "web_fetch" =>
          upsert_tool_trace(
            self.tool_traces,
            trace_id,
            "web_fetch",
            @types.ToolCallKind::Builtin(builtin_type="web_fetch"),
            @types.ToolCallStatus::InProgress,
            input,
          )
        _ =>
          match
            build_code_execution_input_part(
              self.current_server_tool_name,
              input,
            ) {
            Some(part) => self.content_parts.push(part)
            None =>
              upsert_tool_trace(
                self.tool_traces,
                trace_id,
                self.current_server_tool_name,
                @types.ToolCallKind::Builtin(
                  builtin_type=self.current_server_tool_name,
                ),
                @types.ToolCallStatus::InProgress,
                input,
              )
          }
      }
      self.current_server_tool_id = ""
      self.current_server_tool_name = ""
      self.current_server_tool_input.reset()
    }
    "tool_use"
    | "code_execution_tool_result"
    | "bash_code_execution_tool_result"
    | "text_editor_code_execution_tool_result"
    | "web_search_tool_result"
    | "web_fetch_tool_result"
    | "" => ()
    _ =>
      abort(
        "Anthropic accumulator cannot finish unsupported block type: " +
        self.current_block_type,
      )
  }
  self.current_block_type = ""
}

///|
fn AnthropicMessagesAccumulator::parse_current_server_tool_input(
  self : AnthropicMessagesAccumulator,
) -> Json {
  let raw = self.current_server_tool_input.to_string()
  if raw.length() == 0 {
    Json::object({})
  } else {
    @json.parse(raw) catch {
      _ => abort("Anthropic server_tool_use input must be valid JSON: " + raw)
    }
  }
}

///|
fn anthropic_accumulator_has_non_text_parts(
  parts : Array[@types.ResponseContentPart],
) -> Bool {
  for part in parts {
    match part {
      @types.ResponseContentPart::OutputText(_) => ()
      _ => return true
    }
  }
  false
}

///|
/// Get final result
pub fn AnthropicMessagesAccumulator::finish(
  self : AnthropicMessagesAccumulator,
) -> @types.ModelResponse {
  self.finish_current_block()
  let content = self.text.to_string()
  if self.stop_reason == "tool_use" && self.tool_calls.length() > 0 {
    let calls = @types.tool_calls_to_requests(self.tool_calls)
    if self.content_parts.length() > 0 || self.tool_traces.length() > 0 {
      @types.ModelResponse::ToolCallsWithContent(
        tool_calls=calls,
        rich=@types.RichTextResponse::from_parts(
          content~,
          content_parts=self.content_parts,
          annotations=self.annotations,
          tool_traces=self.tool_traces,
        ),
      )
    } else {
      @types.ModelResponse::ToolCalls(calls)
    }
  } else if anthropic_accumulator_has_non_text_parts(self.content_parts) ||
    self.annotations.length() > 0 ||
    self.tool_traces.length() > 0 {
    @types.ModelResponse::RichText(
      @types.RichTextResponse::from_parts(
        content~,
        content_parts=self.content_parts,
        annotations=self.annotations,
        tool_traces=self.tool_traces,
      ),
    )
  } else {
    @types.ModelResponse::Text(content)
  }
}

///|
fn anthropic_accumulator_output_text_length(
  parts : Array[@types.ResponseContentPart],
) -> Int {
  let mut total = 0
  for part in parts {
    match part {
      @types.ResponseContentPart::OutputText(text) =>
        total = total + text.length()
      _ => ()
    }
  }
  total
}
