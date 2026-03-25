///|
/// Gemini GenerateContent API Response to Responses API Response conversion

///|
pub fn response_to_responses(
  response : Json,
  response_id~ : String,
  model~ : String,
) -> Json {
  let parsed = parse_response(response)
  let normalized = normalize_gemini_model_response_for_responses(parsed)
  merge_gemini_reasoning_output_items(
    @openai_responses_contract.model_response_to_responses_json(
      normalized,
      response_id~,
      model~,
    ),
  )
}

///|
fn normalize_gemini_model_response_for_responses(
  response : @types.ModelResponse,
) -> @types.ModelResponse {
  match response {
    @types.ModelResponse::ToolCalls(tool_calls) =>
      @types.ModelResponse::ToolCalls(
        tool_calls.map(normalize_gemini_tool_call_for_responses),
      )
    @types.ModelResponse::ToolCallsWithContent(tool_calls~, rich~) =>
      @types.ModelResponse::ToolCallsWithContent(
        tool_calls=tool_calls.map(normalize_gemini_tool_call_for_responses),
        rich~,
      )
    _ => response
  }
}

///|
fn normalize_gemini_tool_call_for_responses(
  call : @types.ToolCallRequest,
) -> @types.ToolCallRequest {
  {
    id: @interop_util.gemini_to_openai_responses_call_id(call.id),
    name: call.name,
    arguments: call.arguments,
    kind: call.kind,
  }
}

///|
fn merge_gemini_reasoning_output_items(response : Json) -> Json {
  match response {
    Object(fields) =>
      match fields.get("output") {
        Some(Array(output)) => {
          let result : Map[String, Json] = fields
          result["output"] = Json::array(merge_adjacent_reasoning_items(output))
          Json::object(result)
        }
        _ => response
      }
    _ => response
  }
}

///|
fn merge_adjacent_reasoning_items(output : Array[Json]) -> Array[Json] {
  let result : Array[Json] = []
  let mut i = 0
  while i < output.length() {
    match output.get(i) {
      Some(current) =>
        match (current, output.get(i + 1)) {
          (
            { "type": String("reasoning"), "summary": Array(summary), .. },
            Some(
              {
                "type": String("reasoning"),
                "summary": Array(next_summary),
                "encrypted_content": String(encrypted),
                ..
              }
            ),
          ) if summary.length() > 0 && next_summary.length() == 0 => {
            match current {
              Object(current_fields) => {
                let merged : Map[String, Json] = current_fields
                merged["encrypted_content"] = Json::string(encrypted)
                result.push(Json::object(merged))
              }
              _ => result.push(current)
            }
            i = i + 2
          }
          _ => {
            result.push(current)
            i = i + 1
          }
        }
      None => i = i + 1
    }
  }
  result
}
