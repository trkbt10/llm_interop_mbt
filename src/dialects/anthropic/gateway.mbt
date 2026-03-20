///|
/// Anthropic gateway provider behavior

///|
/// Returns the default base URL for the Anthropic Messages API
pub fn default_base_url() -> String {
  "https://api.anthropic.com/v1"
}

///|
/// Builds the completion endpoint path by appending `/messages` to the base path
pub fn anthropic_completion_path(base_path : String) -> String {
  base_path + "/messages"
}

///|
/// Builds authentication headers including the API key and anthropic-version
pub fn auth_headers(api_key : String) -> Map[String, String] {
  let headers : Map[String, String] = {}
  headers["Content-Type"] = "application/json"
  headers["x-api-key"] = api_key
  headers["anthropic-version"] = "2023-06-01"
  headers
}

///|
/// Resolves an incoming HTTP request as an Anthropic Messages API completion.
/// Returns `Some((dialect, model, body))` if the request matches, `None` otherwise.
pub fn anthropic_resolve_completion(
  meth : String,
  path : String,
  body : String,
) -> (String, String, String)? {
  if (path == "/v1/messages" || path.has_prefix("/v1/messages?")) &&
    meth == "POST" {
    return Some(("anthropic", "", body))
  }
  None
}
