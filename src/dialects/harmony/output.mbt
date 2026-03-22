///|
/// ModelResponse to Responses API JSON conversion

///|
/// Convert ModelResponse to Responses API response JSON.
/// The OpenAI dialect owns the canonical Responses API serializer.
pub fn model_response_to_responses_json(
  response : @types.ModelResponse,
  response_id~ : String,
  model~ : String,
) -> Json {
  @openai.model_response_to_responses_json(response, response_id~, model~)
}
