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
  target_dialect : GatewaySurface,
  model : String,
  base_url : String,
  api_key : String,
) -> UpstreamRequest {
  let (origin, base_path) = @utils.parse_url(base_url)
  let from = target_dialect
  let to = provider.api.to_dialect()
  // Apply model alias: map incoming model name to backend model name
  let backend_model = match provider.model_aliases.get(model) {
    Some(mapped) => mapped
    None => model
  }
  let ctx = build_transform_context(provider, backend_model)
  let transformed = transform_request(body, from, to, backend_model, ctx)
  // Replace model name in transformed body if alias was applied
  let final_body = if backend_model != model {
    replace_model_in_body(transformed, backend_model)
  } else {
    transformed
  }
  {
    origin,
    path: provider.api.completion_path(base_path, backend_model, api_key),
    headers: provider.api.auth_headers(api_key),
    body: final_body,
  }
}

///|
/// Replace the "model" field in a JSON body with the given model name
fn replace_model_in_body(body : String, model : String) -> String {
  let json = @json.parse(body) catch { _ => return body }
  match json {
    Object(obj) => {
      obj["model"] = Json::string(model)
      Json::object(obj).stringify()
    }
    _ => body
  }
}

///|
/// Transform request body for a specific provider and model.
/// Convenience for host runtime to call transform_request with correct context.
pub fn transform_for_provider(
  provider : ProviderConfig,
  body : String,
  from : GatewaySurface,
  to : GatewaySurface,
  model : String,
) -> String {
  let ctx = build_transform_context(provider, model)
  transform_request(body, from, to, model, ctx)
}

///|
fn build_transform_context(
  provider : ProviderConfig,
  model : String,
) -> @types.TransformContext {
  for m in provider.models {
    if m.id == model {
      return {
        max_tokens: m.max_tokens,
        max_tokens_field: m.compat.max_tokens_field,
      }
    }
  }
  @types.TransformContext::default()
}

///|
/// Route resolution result
pub(all) enum RouteResult {
  Health
  ListModels
  Completion(dialect~ : GatewaySurface, body~ : String)
  ResponsesApi(body~ : String)
  CompletionWithModel(
    dialect~ : GatewaySurface,
    model~ : String,
    body~ : String
  )
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
  if (path == "/v1/models" || path.has_prefix("/v1/models?")) && meth == "GET" {
    return ListModels
  }
  match self.dialect.resolve_completion(meth, path, body) {
    Some(result) => result
    None => NotFound(path~, dialect=self.dialect.to_string())
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
/// Select provider based on model name
pub fn Gateway::select_backend(
  self : Gateway,
  model : String,
) -> ProviderConfig? {
  // Try exact match in providers
  for _, prov in self.config.providers {
    for m in prov.models {
      if m.id == model {
        return Some(prov)
      }
    }
  }
  // Try pattern-based routing from config
  for _, prov in self.config.providers {
    for pattern in prov.model_patterns {
      if model.has_prefix(pattern) {
        return Some(prov)
      }
    }
  }
  None
}
