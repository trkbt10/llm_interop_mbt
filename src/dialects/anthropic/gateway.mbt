///|
/// Anthropic gateway provider behavior

///|
pub fn anthropic_default_base_url() -> String {
  "https://api.anthropic.com/v1"
}

///|
pub fn anthropic_completion_path(base_path : String) -> String {
  base_path + "/messages"
}

///|
pub fn anthropic_auth_headers(api_key : String) -> Map[String, String] {
  let headers : Map[String, String] = {}
  headers["Content-Type"] = "application/json"
  headers["x-api-key"] = api_key
  headers["anthropic-version"] = "2023-06-01"
  headers
}

///|
pub fn anthropic_resolve_completion(
  meth : String,
  path : String,
  body : String,
) -> (String, String, String)? {
  if path == "/v1/messages" && meth == "POST" {
    return Some(("anthropic", "", body))
  }
  None
}
