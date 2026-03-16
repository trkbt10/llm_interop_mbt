///|
/// Provider-specific behavior consolidated on ModelApi
///
/// All dialect/provider-dependent logic lives here.
/// Adding a new provider = updating only this file.

///|
/// Map ModelApi to chat.Dialect for body transformation
pub fn ModelApi::to_dialect(self : ModelApi) -> @chat.Dialect {
  match self {
    OpenAICompletions | OpenAIResponses => @chat.Dialect::OpenAI
    AnthropicMessages => @chat.Dialect::Anthropic
    GoogleGenerativeAI => @chat.Dialect::Gemini
    _ => @chat.Dialect::OpenAI
  }
}

///|
/// Build upstream path for completion requests
pub fn ModelApi::completion_path(
  self : ModelApi,
  base_path : String,
  model : String,
  api_key : String,
) -> String {
  match self {
    OpenAICompletions | OpenAIResponses => base_path + "/chat/completions"
    AnthropicMessages => base_path + "/messages"
    GoogleGenerativeAI =>
      base_path + "/models/" + model + ":generateContent?key=" + api_key
    _ => base_path + "/chat/completions"
  }
}

///|
/// Build upstream path for model listing
pub fn ModelApi::models_path(
  self : ModelApi,
  base_path : String,
  api_key : String,
) -> String {
  match self {
    GoogleGenerativeAI => base_path + "/models?key=" + api_key
    _ => base_path + "/models"
  }
}

///|
/// Build auth headers for this provider type
pub fn ModelApi::auth_headers(
  self : ModelApi,
  api_key : String,
) -> Map[String, String] {
  let headers : Map[String, String] = {}
  headers["Content-Type"] = "application/json"
  match self {
    AnthropicMessages => {
      headers["x-api-key"] = api_key
      headers["anthropic-version"] = "2023-06-01"
    }
    GoogleGenerativeAI => () // API key in URL
    _ => headers["Authorization"] = "Bearer " + api_key
  }
  headers
}

