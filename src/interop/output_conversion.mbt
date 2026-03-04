///|
/// ModelResponse to Responses API JSON conversion

///|
/// Convert ModelResponse to Responses API response JSON
pub fn model_response_to_responses_json(
  response : @types.ModelResponse,
  response_id~ : String,
  model~ : String,
) -> Json {
  match response {
    @types.ModelResponse::Text(content) =>
      {
        "id": response_id,
        "object": "response",
        "status": "completed",
        "output": Json::array([
          {
            "type": "message",
            "role": "assistant",
            "content": Json::array([{ "type": "output_text", "text": content }]),
          },
        ]),
        "model": model,
      }
    @types.ModelResponse::ToolCalls(calls) => {
      let output : Array[Json] = []
      for call in calls {
        output.push({
          "type": "function_call",
          "id": call.id,
          "call_id": call.id,
          "name": call.name,
          "arguments": call.arguments.stringify(),
          "status": "completed",
        })
      }
      {
        "id": response_id,
        "object": "response",
        "status": "completed",
        "output": Json::array(output),
        "model": model,
      }
    }
    @types.ModelResponse::ModelError(msg) =>
      { "error": { "type": "error", "message": msg } }
    @types.ModelResponse::RateLimited(retry_after~) =>
      {
        "error": {
          "type": "rate_limit_error",
          "message": "Rate limited",
          "retry_after": retry_after,
        },
      }
  }
}
