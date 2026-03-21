///|
/// Gemini GenerateContent API Response to Responses API Response conversion
///
/// Converts Google Gemini responses to OpenAI Responses API format.
/// Flow: Gemini Response -> Responses API Response

///|
/// Convert Gemini GenerateContent response JSON to Responses API response JSON
pub fn response_to_responses(
  response : Json,
  response_id~ : String,
  model~ : String,
) -> Json {
  match response {
    { "candidates": Array(candidates), .. } =>
      if candidates.length() > 0 {
        let candidate = candidates[0]
        match candidate {
          { "content": { "parts": Array(parts), .. }, .. } => {
            let output = build_responses_output_from_gemini(parts)
            {
              "id": response_id,
              "object": "response",
              "status": "completed",
              "output": Json::array(output),
              "model": model,
            }
          }
          { "finishReason": String("SAFETY"), .. } =>
            {
              "error": {
                "type": "content_filter",
                "message": "Response blocked by safety filters",
              },
            }
          _ =>
            {
              "error": {
                "type": "error",
                "message": "Invalid candidate format",
              },
            }
        }
      } else {
        { "error": { "type": "error", "message": "No candidates in response" } }
      }
    { "error": { "message": String(msg), .. }, .. } =>
      { "error": { "type": "error", "message": msg } }
    _ => { "error": { "type": "error", "message": "Unknown response format" } }
  }
}

///|
/// Build Responses API output array from Gemini parts
fn build_responses_output_from_gemini(parts : Array[Json]) -> Array[Json] {
  let tool_outputs : Array[Json] = []
  let text_parts : Array[Json] = []
  let mut call_index = 0
  for part in parts {
    match part {
      { "text": String(text), .. } =>
        text_parts.push({ "type": "output_text", "text": text })
      { "functionCall": { "name": String(name), "args": args, .. }, .. } => {
        let gemini_id = @interop_util.generate_gemini_tool_call_id(
          name, call_index,
        )
        let call_id = @interop_util.gemini_to_openai_responses_call_id(
          gemini_id,
        )
        if name == @types.web_search_tool_name() {
          tool_outputs.push(
            @openai.build_responses_web_search_call(call_id, args),
          )
        } else {
          tool_outputs.push(
            @openai.build_responses_function_call(call_id, name, args),
          )
        }
        call_index = call_index + 1
      }
      _ => ()
    }
  }
  @openai.assemble_responses_output(text_parts, tool_outputs)
}

///|
/// Parse Gemini response JSON and convert to ModelResponse
pub fn parse_as_model_response(response : Json) -> @types.ModelResponse {
  parse_response(response)
}
