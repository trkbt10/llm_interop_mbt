///|
/// Gemini streaming accumulator
/// Feeds Gemini SSE events and produces a ModelResponse.

///|
pub struct GeminiAccumulator {
  text : StringBuilder
  tool_calls : Array[@types.ToolCallAcc]
  mut finished : Bool
}

///|
pub fn GeminiAccumulator::new() -> GeminiAccumulator {
  { text: StringBuilder::new(), tool_calls: [], finished: false }
}

///|
/// Feed a single SSE event from Gemini streamGenerateContent
pub fn GeminiAccumulator::feed(
  self : GeminiAccumulator,
  event : @sse.SseEvent,
) -> Unit {
  match parse_stream_chunk(event.data) {
    Some((text, calls)) => {
      if text.length() > 0 {
        self.text.write_string(text)
      }
      for call in calls {
        let tc : @types.ToolCallAcc = {
          id: call.id,
          name: call.name,
          arguments: StringBuilder::new(),
        }
        tc.arguments.write_string(call.arguments.stringify())
        self.tool_calls.push(tc)
      }
    }
    None => ()
  }
}

///|
/// Finalize and produce ModelResponse
pub fn GeminiAccumulator::finish(
  self : GeminiAccumulator,
) -> @types.ModelResponse {
  self.finished = true
  if self.tool_calls.length() > 0 {
    let calls : Array[@types.ToolCallRequest] = []
    for tc in self.tool_calls {
      let arguments = @json.parse(tc.arguments.to_string()) catch { _ => {} }
      calls.push(
        @types.ToolCallRequest::new(id=tc.id, name=tc.name, arguments~),
      )
    }
    @types.ModelResponse::ToolCalls(calls)
  } else {
    @types.ModelResponse::Text(self.text.to_string())
  }
}

///|
/// Convert a non-streaming Gemini response into a synthetic SSE event
/// that GeminiToResponsesTranslator can process.
pub fn non_streaming_to_synthetic_events(json : Json) -> Array[@sse.SseEvent] {
  [{ event: "", data: json }]
}

///|
/// Convenience: accumulate full SSE text into ModelResponse
pub fn accumulate_gemini(body : String) -> @types.ModelResponse {
  let acc = GeminiAccumulator::new()
  let parsed = @sse.parse_sse_chunk(body)
  for event in parsed.events {
    acc.feed(event)
  }
  acc.finish()
}
