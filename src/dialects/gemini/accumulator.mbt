///|
/// Gemini streaming accumulator
/// Feeds Gemini SSE events and produces a ModelResponse.

///|
struct GeminiAccumulator {
  text : StringBuilder
  tool_calls : Array[@types.ToolCallAcc]
  mut annotations : Array[@types.ResponseAnnotation]
}

///|
pub fn GeminiAccumulator::new() -> GeminiAccumulator {
  { text: StringBuilder::new(), tool_calls: [], annotations: [] }
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
  self.refresh_annotations(event.data)
}

///|
/// Finalize and produce ModelResponse
pub fn GeminiAccumulator::finish(
  self : GeminiAccumulator,
) -> @types.ModelResponse {
  let content = normalize_structured_output_text(self.text.to_string())
  if self.tool_calls.length() > 0 {
    let calls : Array[@types.ToolCallRequest] = []
    for tc in self.tool_calls {
      let arguments = @json.parse(tc.arguments.to_string()) catch {
        _ =>
          abort(
            "Gemini tool call arguments must be valid JSON: " +
            tc.arguments.to_string(),
          )
      }
      calls.push(
        @types.ToolCallRequest::new(id=tc.id, name=tc.name, arguments~),
      )
    }
    if content.length() > 0 || self.annotations.length() > 0 {
      @types.ModelResponse::ToolCallsWithContent(
        tool_calls=calls,
        rich=@types.RichTextResponse::from_parts(
          content~,
          content_parts=[@types.ResponseContentPart::OutputText(content)],
          annotations=self.annotations,
        ),
      )
    } else {
      @types.ModelResponse::ToolCalls(calls)
    }
  } else if self.annotations.length() > 0 {
    @types.ModelResponse::RichText(
      @types.RichTextResponse::from_parts(
        content~,
        content_parts=[@types.ResponseContentPart::OutputText(content)],
        annotations=self.annotations,
      ),
    )
  } else {
    @types.ModelResponse::Text(content)
  }
}

///|
fn GeminiAccumulator::refresh_annotations(
  self : GeminiAccumulator,
  chunk_json : Json,
) -> Unit {
  let rendered_text = self.text.to_string()
  if rendered_text.length() == 0 {
    return
  }
  match chunk_json {
    { "candidates": Array(candidates), .. } if candidates.length() > 0 => {
      let annotations = collect_gemini_grounding_annotations(
        candidates[0],
        rendered_text,
      )
      if annotations.length() > 0 {
        self.annotations = annotations
      }
    }
    _ => ()
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
