///|
/// Harmony (gpt-oss) Chat Completions stream accumulator

///|
/// Groq/OpenAI Chat Completions with Harmony format accumulator
/// gpt-oss models return reasoning/channel fields in addition to content/tool_calls
/// This accumulator captures all Harmony-specific fields for full interoperability
pub struct HarmonyAccumulator {
  /// Final output text (channel=final)
  text : StringBuilder
  /// Reasoning/chain-of-thought (channel=analysis)
  reasoning : StringBuilder
  /// Current channel being accumulated
  mut current_channel : String
  /// Tool calls
  tool_calls : Array[@types.ToolCallAcc]
  /// Finish reason
  mut finish_reason : String
}

///|
pub fn HarmonyAccumulator::new() -> HarmonyAccumulator {
  {
    text: StringBuilder::new(),
    reasoning: StringBuilder::new(),
    current_channel: "",
    tool_calls: [],
    finish_reason: "",
  }
}

///|
/// Process Harmony Chat Completions chunk
/// Handles delta.reasoning (channel=analysis), delta.content (channel=final), delta.tool_calls
pub fn HarmonyAccumulator::feed(
  self : HarmonyAccumulator,
  event : @sse.SseEvent,
) -> Unit {
  match event.data {
    { "choices": Array(choices), .. } =>
      if choices.length() > 0 {
        let choice = choices[0]
        match choice {
          { "delta": delta, .. } => {
            // Update current channel
            match delta {
              { "channel": String(ch), .. } => self.current_channel = ch
              _ => ()
            }
            // Reasoning delta (channel=analysis)
            match delta {
              { "reasoning": String(r), .. } => self.reasoning.write_string(r)
              _ => ()
            }
            // Content delta (channel=final)
            match delta {
              { "content": String(c), .. } =>
                if c.length() > 0 {
                  self.text.write_string(c)
                }
              _ => ()
            }
            // Tool calls delta
            match delta {
              { "tool_calls": Array(tc_deltas), .. } =>
                for tc in tc_deltas {
                  self.process_tool_call_delta(tc)
                }
              _ => ()
            }
          }
          _ => ()
        }
        // finish_reason
        match choice {
          { "finish_reason": String(fr), .. } => self.finish_reason = fr
          _ => ()
        }
      }
    _ => ()
  }
}

///|
fn HarmonyAccumulator::process_tool_call_delta(
  self : HarmonyAccumulator,
  tc : Json,
) -> Unit {
  @types.process_tool_call_delta(self.tool_calls, tc)
}

///|
/// Get final result
pub fn HarmonyAccumulator::finish(
  self : HarmonyAccumulator,
) -> @types.ModelResponse {
  if self.finish_reason == "tool_calls" && self.tool_calls.length() > 0 {
    @types.ModelResponse::ToolCalls(@types.tool_calls_to_requests(self.tool_calls))
  } else {
    @types.ModelResponse::Text(self.text.to_string())
  }
}

///|
/// Get accumulated reasoning (for logging/debugging)
pub fn HarmonyAccumulator::get_reasoning(self : HarmonyAccumulator) -> String {
  self.reasoning.to_string()
}
