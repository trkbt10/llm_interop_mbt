///|
/// Model listing - config-based and remote response parsing

///|
/// Prepare an upstream request for listing models
pub fn prepare_models_request(
  provider : ProviderConfig,
  base_url : String,
  api_key : String,
) -> UpstreamRequest {
  let (origin, base_path) = @utils.parse_url(base_url)
  {
    origin,
    path: provider.api.models_path(base_path, api_key),
    headers: provider.api.auth_headers(api_key),
    body: "",
  }
}

///|
/// Parse model list response from various provider formats into unified format
pub fn parse_models_response(
  response_text : String,
  provider_id : String,
) -> Array[Json] {
  let json = @json.parse(response_text) catch { _ => return [] }
  let data = match json {
    { "data": Array(d), .. } => d // OpenAI format
    { "models": Array(d), .. } => d // Anthropic format
    _ => return []
  }
  let models : Array[Json] = []
  for m in data {
    match m {
      { "id": String(id), .. } => {
        let obj : Map[String, Json] = {}
        obj["id"] = Json::string(id)
        obj["object"] = Json::string("model")
        obj["owned_by"] = Json::string(provider_id)
        models.push(Json::object(obj))
      }
      _ => ()
    }
  }
  models
}

///|
/// Convert a ModelConfig to Codex model/list JSON format
pub fn model_config_to_codex_model_json(
  m : ModelConfig,
  provider_id : String,
) -> Json {
  let obj : Map[String, Json] = {}
  obj["id"] = Json::string(m.id)
  obj["model"] = Json::string(m.id)
  obj["displayName"] = Json::string(m.name)
  obj["hidden"] = false.to_json()
  obj["isDefault"] = false.to_json()
  obj["modelProvider"] = Json::string(provider_id)
  let modalities : Array[Json] = []
  for modality in m.input {
    match modality {
      Text => modalities.push(Json::string("text"))
      Image => modalities.push(Json::string("image"))
    }
  }
  obj["inputModalities"] = Json::array(modalities)
  if m.compat.supports_reasoning_effort {
    obj["defaultReasoningEffort"] = Json::string("medium")
    obj["supportedReasoningEfforts"] = Json::array([
      { "reasoning_effort": "low", "description": "Fast responses" },
      { "reasoning_effort": "medium", "description": "Balanced" },
      { "reasoning_effort": "high", "description": "Thorough reasoning" },
    ])
  }
  Json::object(obj)
}

///|
/// Enrich a remote model ID with config metadata if available,
/// otherwise return minimal Codex model/list entry
pub fn enrich_remote_model_json(
  model_id : String,
  provider_id : String,
  configured_models : Array[ModelConfig],
) -> Json {
  for m in configured_models {
    if m.id == model_id {
      return model_config_to_codex_model_json(m, provider_id)
    }
  }
  let obj : Map[String, Json] = {}
  obj["id"] = Json::string(model_id)
  obj["model"] = Json::string(model_id)
  obj["displayName"] = Json::string(model_id)
  obj["hidden"] = false.to_json()
  obj["isDefault"] = false.to_json()
  obj["modelProvider"] = Json::string(provider_id)
  obj["inputModalities"] = Json::array([Json::string("text")])
  Json::object(obj)
}

///|
/// List models from gateway config (no network)
pub fn Gateway::list_configured_models(self : Gateway) -> Array[Json] {
  let models : Array[Json] = []
  for backend in self.config.backends {
    for m in backend.provider.models {
      let obj : Map[String, Json] = {}
      obj["id"] = Json::string(m.id)
      obj["object"] = Json::string("model")
      obj["owned_by"] = Json::string(backend.provider.id)
      models.push(Json::object(obj))
    }
  }
  for prov_id, prov in self.config.providers {
    for m in prov.models {
      let obj : Map[String, Json] = {}
      obj["id"] = Json::string(m.id)
      obj["object"] = Json::string("model")
      obj["owned_by"] = Json::string(prov_id)
      models.push(Json::object(obj))
    }
  }
  models
}
