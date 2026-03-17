///|
/// Gemini gateway provider behavior

///|
pub fn gemini_default_base_url() -> String {
  "https://generativelanguage.googleapis.com/v1beta"
}

///|
pub fn gemini_completion_path(
  base_path : String,
  model : String,
  api_key : String,
) -> String {
  base_path + "/models/" + model + ":generateContent?key=" + api_key
}

///|
pub fn gemini_models_path(base_path : String, api_key : String) -> String {
  base_path + "/models?key=" + api_key
}

///|
pub fn gemini_auth_headers() -> Map[String, String] {
  let headers : Map[String, String] = {}
  headers["Content-Type"] = "application/json"
  // API key is passed in URL, no auth header needed
  headers
}

///|
pub fn gemini_resolve_completion(
  meth : String,
  path : String,
  body : String,
) -> (String, String, String)? {
  if path.has_prefix("/v1/models/") &&
    path.has_suffix(":generateContent") &&
    meth == "POST" {
    let model = extract_gemini_model_from_path(path)
    return Some(("gemini", model, body))
  }
  None
}

///|
/// Extract model name from Gemini generateContent path
/// Path format: /v1/models/{model}:generateContent
pub fn extract_gemini_model_from_path(path : String) -> String {
  let prefix = "/v1/models/"
  let suffix = ":generateContent"
  if path.has_prefix(prefix) && path.has_suffix(suffix) {
    let start = prefix.length()
    let end = path.length() - suffix.length()
    if end > start {
      let mut result = ""
      let mut idx = 0
      for c in path {
        if idx >= start && idx < end {
          result = result + c.to_string()
        }
        idx = idx + 1
      }
      result
    } else {
      ""
    }
  } else {
    ""
  }
}
