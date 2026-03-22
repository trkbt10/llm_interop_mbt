///|
/// Gemini gateway provider behavior

///|
/// Returns the default base URL for the Gemini API
pub fn default_base_url() -> String {
  "https://generativelanguage.googleapis.com/v1beta"
}

///|
/// Builds the generateContent endpoint path including model and API key
pub fn completion_path(
  base_path : String,
  model : String,
  api_key : String,
) -> String {
  base_path + "/models/" + model + ":generateContent?key=" + api_key
}

///|
/// Builds the streamGenerateContent endpoint path for streaming responses
pub fn stream_completion_path(
  base_path : String,
  model : String,
  api_key : String,
) -> String {
  base_path +
  "/models/" +
  model +
  ":streamGenerateContent?alt=sse&key=" +
  api_key
}

///|
/// Builds the models listing endpoint path with API key
pub fn models_path(base_path : String, api_key : String) -> String {
  base_path + "/models?key=" + api_key
}

///|
/// Builds request headers (API key is passed via URL, not headers)
pub fn auth_headers() -> Map[String, String] {
  let headers : Map[String, String] = {}
  headers["Content-Type"] = "application/json"
  // API key is passed in URL, no auth header needed
  headers
}

///|
/// Resolves an incoming HTTP request as a Gemini generateContent call.
/// Returns `Some((dialect, model, body))` if the request matches, `None` otherwise.
pub fn resolve_completion(
  meth : String,
  path : String,
  body : String,
) -> (String, String, String)? {
  if meth != "POST" || not(path.has_prefix("/v1/models/")) {
    return None
  }
  if path.has_suffix(":generateContent") {
    let model = extract_model_from_path(path)
    return Some(("gemini", model, body))
  }
  // Streaming endpoint: :streamGenerateContent?alt=sse
  if path.contains(":streamGenerateContent") {
    let model = extract_model_from_stream_path(path)
    return Some(("gemini", model, body))
  }
  None
}

///|
/// Extract model name from Gemini streamGenerateContent path
/// Path format: /v1/models/{model}:streamGenerateContent?alt=sse&key=...
pub fn extract_model_from_stream_path(path : String) -> String {
  let prefix = "/v1/models/"
  if path.has_prefix(prefix) {
    let start = prefix.length()
    // Find the position of the suffix
    let mut end = path.length()
    let mut idx = 0
    for c in path {
      if idx >= start && c == ':' {
        end = idx
        break
      }
      idx = idx + 1
    }
    if end > start {
      let mut result = ""
      let mut i = 0
      for c in path {
        if i >= start && i < end {
          result = result + c.to_string()
        }
        i = i + 1
      }
      result
    } else {
      ""
    }
  } else {
    ""
  }
}

///|
/// Extract model name from Gemini generateContent path
/// Path format: /v1/models/{model}:generateContent
pub fn extract_model_from_path(path : String) -> String {
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
