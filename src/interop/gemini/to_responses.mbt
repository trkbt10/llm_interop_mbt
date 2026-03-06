///|
/// Gemini GenerateContent API Response to Responses API Response conversion
///
/// Converts Google Gemini responses to OpenAI Responses API format.
/// Flow: Gemini Response -> Responses API Response

///|
/// Convert Gemini GenerateContent response JSON to Responses API response JSON
pub fn gemini_response_to_responses(
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
  let output : Array[Json] = []
  let text_parts : Array[Json] = []
  let mut call_index = 0
  for part in parts {
    match part {
      { "text": String(text), .. } =>
        text_parts.push({ "type": "output_text", "text": text })
      { "functionCall": { "name": String(name), "args": args, .. }, .. } => {
        // Gemini doesn't have native IDs, generate synthetic one
        let call_id = @interop_util.generate_gemini_tool_call_id(
          name, call_index,
        )
        // Convert to Responses API format
        let responses_call_id = @interop_util.gemini_to_openai_responses_call_id(
          call_id,
        )
        if name == "web_search" {
          output.push({
            "type": "web_search_call",
            "id": responses_call_id,
            "status": "completed",
            "action": build_web_search_action(args),
          })
        } else {
          output.push({
            "type": "function_call",
            "id": responses_call_id,
            "call_id": responses_call_id,
            "name": name,
            "arguments": args.stringify(),
            "status": "completed",
          })
        }
        call_index = call_index + 1
      }
      _ => ()
    }
  }
  // Add message output if there's any text
  if text_parts.length() > 0 {
    let message_output : Array[Json] = [
      {
        "type": "message",
        "role": "assistant",
        "content": Json::array(text_parts),
      },
    ]
    for o in output {
      message_output.push(o)
    }
    return message_output
  }
  output
}

///|
fn build_web_search_action(input : Json) -> Json {
  let action : Map[String, Json] = { "type": Json::string("search") }
  match input {
    { "query": String(query), .. } => action["query"] = Json::string(query)
    _ => ()
  }
  Json::object(action)
}

///|
/// Parse Gemini response JSON and convert to ModelResponse
pub fn parse_gemini_as_model_response(response : Json) -> @types.ModelResponse {
  @protocol.parse_gemini_response(response)
}
