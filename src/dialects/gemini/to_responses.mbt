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
  let reasoning_outputs : Array[Json] = []
  let mut call_index = 0
  // Gemini parts → Responses API output items
  // Ref: https://ai.google.dev/api/generate-content — Part types
  //   text → output_text
  //   functionCall → function_call
  //   executableCode → output_text (code block)
  //   codeExecutionResult → output_text (execution result)
  for part in parts {
    let thought_signature = match part {
      { "thoughtSignature": String(value), .. } => Some(value)
      _ => None
    }
    match part {
      // Ref: Part.text — {"text":"..."} → output_text
      { "text": String(text), "thought": True, .. } =>
        reasoning_outputs.push(
          @openai.build_responses_reasoning_item(
            text,
            encrypted_content=thought_signature,
          ),
        )
      { "text": String(text), .. } => {
        match thought_signature {
          Some(value) =>
            reasoning_outputs.push(
              @openai.build_responses_reasoning_item(
                "",
                encrypted_content=Some(value),
              ),
            )
          None => ()
        }
        text_parts.push({ "type": "output_text", "text": text })
      }
      // Ref: Part.functionCall — {"functionCall":{"name":"...","args":{...}}} → function_call
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
        match thought_signature {
          Some(value) =>
            reasoning_outputs.push(
              @openai.build_responses_reasoning_item(
                "",
                encrypted_content=Some(value),
              ),
            )
          None => ()
        }
        call_index = call_index + 1
      }
      // Inference: docs/upstream/gemini-generate-content.md:52-57,3433-3434
      // documents code execution support, but not this concrete Part key.
      // Structure: {"executableCode":{"language":"PYTHON","code":"..."}}
      {
        "executableCode": { "language": String(lang), "code": String(code), .. },
        ..
      } =>
        text_parts.push({
          "type": "output_text",
          "text": "```\{lang.to_lower()}\n\{code}\n```",
        })
      // Inference: docs/upstream/gemini-generate-content.md:52-57,3433-3434
      // documents code execution support, but not this concrete Part key.
      // Structure: {"codeExecutionResult":{"outcome":"OUTCOME_OK","output":"..."}}
      {
        "codeExecutionResult": {
          "outcome": String(outcome),
          "output": String(output),
          ..
        },
        ..
      } =>
        text_parts.push({
          "type": "output_text",
          "text": "Execution [\{outcome}]: \{output}",
        })
      _ => ()
    }
  }
  @openai.assemble_responses_output(
    normalize_output_text_json_items(text_parts),
    tool_outputs,
    reasoning_outputs~,
  )
}

///|
/// Parse Gemini response JSON and convert to ModelResponse
pub fn parse_as_model_response(response : Json) -> @types.ModelResponse {
  parse_response(response)
}
