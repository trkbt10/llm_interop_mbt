///|
/// Gateway core - routing, backend selection, upstream request preparation

///|
/// Prepared upstream request, ready for HTTP transport
pub(all) struct UpstreamRequest {
  origin : String
  path : String
  headers : Map[String, String]
  body : String
}

///|
/// Prepare an upstream request for a completion endpoint.
/// Takes already-expanded base_url and api_key (env vars resolved by caller).
pub fn prepare_upstream(
  provider : ProviderConfig,
  body : String,
  target_dialect : @chat.Dialect,
  model : String,
  base_url : String,
  api_key : String,
) -> UpstreamRequest {
  let (origin, base_path) = @utils.parse_url(base_url)
  let from = target_dialect
  let to = provider.api.to_dialect()
  {
    origin,
    path: provider.api.completion_path(base_path, model, api_key),
    headers: provider.api.auth_headers(api_key),
    body: @chat.transform_request(body, from, to, model),
  }
}

///|
/// Route resolution result
pub(all) enum RouteResult {
  Health
  ListModels
  Completion(dialect~ : @chat.Dialect, body~ : String)
  ResponsesApi(body~ : String)
  CompletionWithModel(dialect~ : @chat.Dialect, model~ : String, body~ : String)
  NotFound(path~ : String, dialect~ : String)
} derive(Show)

///|
/// Resolve route from method, path, and body
/// Pure routing logic with no side effects
pub fn Gateway::resolve(
  self : Gateway,
  meth : String,
  path : String,
  body : String,
) -> RouteResult {
  if path == "/" || path == "/health" {
    return Health
  }
  if path == "/v1/models" && meth == "GET" {
    return ListModels
  }
  match self.dialect {
    GatewaySurface::OpenAI => {
      if path == "/v1/chat/completions" && meth == "POST" {
        return Completion(dialect=@chat.Dialect::OpenAI, body~)
      }
      if path == "/v1/responses" && meth == "POST" {
        return ResponsesApi(body~)
      }
    }
    GatewaySurface::Anthropic => {
      if path == "/v1/messages" && meth == "POST" {
        return Completion(dialect=@chat.Dialect::Anthropic, body~)
      }
    }
    GatewaySurface::Gemini => {
      if path.has_prefix("/v1/models/") &&
        path.has_suffix(":generateContent") &&
        meth == "POST" {
        let model = extract_model_from_path(path)
        return CompletionWithModel(dialect=@chat.Dialect::Gemini, model~, body~)
      }
    }
  }
  NotFound(path~, dialect=self.dialect.to_string())
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

///|
/// Gateway state
pub(all) struct Gateway {
  config : GatewayConfig
  dialect : GatewaySurface
}

///|
pub fn Gateway::new(
  config : GatewayConfig,
  dialect : GatewaySurface,
) -> Gateway {
  { config, dialect }
}

///|
/// Select backend based on model name
pub fn Gateway::select_backend(
  self : Gateway,
  model : String,
) -> BackendConfig? {
  // First try exact match in backends
  for backend in self.config.backends {
    for m in backend.provider.models {
      if m.id == model {
        return Some(backend)
      }
    }
  }
  // Try exact match in providers
  for _, prov in self.config.providers {
    for m in prov.models {
      if m.id == model {
        return Some({ id: prov.id, provider: prov, weight: 1 })
      }
    }
  }
  // Try pattern-based routing from config
  for _, prov in self.config.providers {
    for pattern in prov.model_patterns {
      if model.has_prefix(pattern) {
        return Some({ id: prov.id, provider: prov, weight: 1 })
      }
    }
  }
  None
}
