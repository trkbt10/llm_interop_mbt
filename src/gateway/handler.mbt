///|
/// Gateway HTTP request handler

///|
/// HTTP response helper
pub(all) struct HttpResponse {
  status : Int
  headers : Map[String, String]
  body : String
} derive(Show)

///|
pub fn HttpResponse::json(status : Int, body : Json) -> HttpResponse {
  let headers : Map[String, String] = {}
  headers["Content-Type"] = "application/json"
  { status, headers, body: body.stringify() }
}

///|
pub fn HttpResponse::error(status : Int, message : String) -> HttpResponse {
  HttpResponse::json(status, { "error": { "message": message } })
}

///|
pub fn HttpResponse::ok(body : Json) -> HttpResponse {
  HttpResponse::json(200, body)
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
  // Try providers
  for _, prov in self.config.providers {
    for m in prov.models {
      if m.id == model {
        return Some({ id: prov.id, provider: prov, weight: 1 })
      }
    }
  }
  // Fallback to first backend
  if self.config.backends.length() > 0 {
    return Some(self.config.backends[0])
  }
  // Fallback to first provider
  for _, prov in self.config.providers {
    return Some({ id: prov.id, provider: prov, weight: 1 })
  }
  None
}

///|
/// Route request based on path
pub fn Gateway::route(
  self : Gateway,
  meth : String,
  path : String,
  body : String,
) -> HttpResponse {
  // Health check
  if path == "/" || path == "/health" {
    return HttpResponse::ok({
      "status": "ok",
      "dialect": self.dialect.to_string(),
    })
  }
  // Chat completions endpoint
  if path == "/v1/chat/completions" && meth == "POST" {
    return self.handle_chat_completions(body)
  }
  // Models endpoint
  if path == "/v1/models" && meth == "GET" {
    return self.handle_list_models()
  }
  HttpResponse::error(404, "Not found: " + path)
}

///|
/// Handle /v1/chat/completions
fn Gateway::handle_chat_completions(
  self : Gateway,
  body : String,
) -> HttpResponse {
  let json = @json.parse(body) catch {
    _ => return HttpResponse::error(400, "Invalid JSON body")
  }
  // Extract model from request
  let model = match json {
    { "model": String(m), .. } => m
    _ => return HttpResponse::error(400, "model field is required")
  }
  // Select backend
  let backend = match self.select_backend(model) {
    Some(b) => b
    None =>
      return HttpResponse::error(
        503,
        "No backend available for model: " + model,
      )
  }
  // For now, return a placeholder - actual proxy will be implemented
  HttpResponse::ok({
    "id": "chatcmpl-gateway",
    "object": "chat.completion",
    "model": model,
    "backend": backend.id,
    "message": "Gateway routing successful (proxy not yet implemented)",
  })
}

///|
/// Handle /v1/models
fn Gateway::handle_list_models(self : Gateway) -> HttpResponse {
  let models : Array[Json] = []
  // Add models from backends
  for backend in self.config.backends {
    for m in backend.provider.models {
      let obj : Map[String, Json] = {}
      obj["id"] = Json::string(m.id)
      obj["object"] = Json::string("model")
      obj["owned_by"] = Json::string(backend.provider.id)
      models.push(Json::object(obj))
    }
  }
  // Add models from providers
  for prov_id, prov in self.config.providers {
    for m in prov.models {
      let obj : Map[String, Json] = {}
      obj["id"] = Json::string(m.id)
      obj["object"] = Json::string("model")
      obj["owned_by"] = Json::string(prov_id)
      models.push(Json::object(obj))
    }
  }
  HttpResponse::ok({ "object": "list", "data": Json::array(models) })
}

///|
/// Add CORS headers
pub fn add_cors_headers(resp : HttpResponse) -> HttpResponse {
  resp.headers["Access-Control-Allow-Origin"] = "*"
  resp.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
  resp.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
  resp
}
