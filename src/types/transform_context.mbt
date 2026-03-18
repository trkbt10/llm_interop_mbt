///|
/// Context for dialect request transformations.
/// Carries model-specific parameters that dialects need
/// to produce correct API requests.
pub(all) struct TransformContext {
  /// Model's configured max output tokens
  max_tokens : Int
  /// API field name for max tokens (e.g. "max_tokens", "max_completion_tokens")
  max_tokens_field : String
}

///|
/// Creates a default TransformContext with zero max_tokens and "max_tokens" field name.
pub fn TransformContext::default() -> TransformContext {
  { max_tokens: 0, max_tokens_field: "max_tokens" }
}

///|
/// Generation parameters extracted from any dialect's request format.
/// Used as an intermediate representation for cross-dialect parameter mapping.
pub(all) struct GenerationParams {
  max_tokens : Json
  temperature : Json
  top_p : Json
  top_k : Json
  stop : Json
  stream : Json
}

///|
/// Creates a GenerationParams with all fields set to null.
pub fn GenerationParams::empty() -> GenerationParams {
  {
    max_tokens: Json::null(),
    temperature: Json::null(),
    top_p: Json::null(),
    top_k: Json::null(),
    stop: Json::null(),
    stream: Json::null(),
  }
}

///|
/// Extract generation parameters from OpenAI Chat Completions format
pub fn GenerationParams::from_openai(json : Json) -> GenerationParams {
  let params = GenerationParams::empty()
  let params = match json {
    { "max_tokens": Number(_) as n, .. } => { ..params, max_tokens: n }
    { "max_completion_tokens": Number(_) as n, .. } =>
      { ..params, max_tokens: n }
    _ => params
  }
  let params = match json {
    { "temperature": Number(_) as n, .. } => { ..params, temperature: n }
    _ => params
  }
  let params = match json {
    { "top_p": Number(_) as n, .. } => { ..params, top_p: n }
    _ => params
  }
  let params = match json {
    { "top_k": Number(_) as n, .. } => { ..params, top_k: n }
    _ => params
  }
  let params = match json {
    { "stop": Array(_) as a, .. } => { ..params, stop: a }
    { "stop": String(_) as s, .. } => { ..params, stop: Json::array([s]) }
    _ => params
  }
  let params = match json {
    { "stream": True, .. } => { ..params, stream: Json::boolean(true) }
    { "stream": False, .. } => { ..params, stream: Json::boolean(false) }
    _ => params
  }
  params
}

///|
/// Extract generation parameters from Anthropic Messages format
pub fn GenerationParams::from_anthropic(json : Json) -> GenerationParams {
  let params = GenerationParams::empty()
  let params = match json {
    { "max_tokens": Number(_) as n, .. } => { ..params, max_tokens: n }
    _ => params
  }
  let params = match json {
    { "temperature": Number(_) as n, .. } => { ..params, temperature: n }
    _ => params
  }
  let params = match json {
    { "top_p": Number(_) as n, .. } => { ..params, top_p: n }
    _ => params
  }
  let params = match json {
    { "top_k": Number(_) as n, .. } => { ..params, top_k: n }
    _ => params
  }
  let params = match json {
    { "stop_sequences": Array(_) as a, .. } => { ..params, stop: a }
    _ => params
  }
  let params = match json {
    { "stream": True, .. } => { ..params, stream: Json::boolean(true) }
    { "stream": False, .. } => { ..params, stream: Json::boolean(false) }
    _ => params
  }
  params
}

///|
/// Extract generation parameters from Gemini GenerateContent format
pub fn GenerationParams::from_gemini(json : Json) -> GenerationParams {
  let params = GenerationParams::empty()
  let config = match json {
    { "generationConfig": Object(_) as cfg, .. } => cfg
    _ => return params
  }
  let params = match config {
    { "maxOutputTokens": Number(_) as n, .. } => { ..params, max_tokens: n }
    _ => params
  }
  let params = match config {
    { "temperature": Number(_) as n, .. } => { ..params, temperature: n }
    _ => params
  }
  let params = match config {
    { "topP": Number(_) as n, .. } => { ..params, top_p: n }
    _ => params
  }
  let params = match config {
    { "topK": Number(_) as n, .. } => { ..params, top_k: n }
    _ => params
  }
  let params = match config {
    { "stopSequences": Array(_) as a, .. } => { ..params, stop: a }
    _ => params
  }
  params
}

///|
/// Apply generation parameters to an OpenAI Chat Completions request object.
pub fn GenerationParams::apply_to_openai(
  self : GenerationParams,
  obj : Map[String, Json],
  ctx : TransformContext,
) -> Unit {
  if self.max_tokens is Number(_) {
    obj[ctx.max_tokens_field] = self.max_tokens
  }
  if self.temperature is Number(_) {
    obj["temperature"] = self.temperature
  }
  if self.top_p is Number(_) {
    obj["top_p"] = self.top_p
  }
  if self.stop is Array(_) {
    obj["stop"] = self.stop
  }
  if self.stream is True {
    obj["stream"] = self.stream
  }
}

///|
/// Apply generation parameters to an Anthropic Messages request object.
/// Uses model config default for max_tokens when not specified (required field).
pub fn GenerationParams::apply_to_anthropic(
  self : GenerationParams,
  obj : Map[String, Json],
  ctx : TransformContext,
) -> Unit {
  // max_tokens is required for Anthropic
  match self.max_tokens {
    Number(_) => obj["max_tokens"] = self.max_tokens
    _ =>
      if ctx.max_tokens > 0 {
        obj["max_tokens"] = Json::number(ctx.max_tokens.to_double())
      }
  }
  if self.temperature is Number(_) {
    obj["temperature"] = self.temperature
  }
  if self.top_p is Number(_) {
    obj["top_p"] = self.top_p
  }
  if self.top_k is Number(_) {
    obj["top_k"] = self.top_k
  }
  if self.stop is Array(_) {
    obj["stop_sequences"] = self.stop
  }
  if self.stream is True {
    obj["stream"] = self.stream
  }
}

///|
/// Apply generation parameters to a Gemini GenerateContent request object
/// as generationConfig.
pub fn GenerationParams::apply_to_gemini(
  self : GenerationParams,
  obj : Map[String, Json],
  _ctx : TransformContext,
) -> Unit {
  let config : Map[String, Json] = {}
  let mut has_config = false
  if self.max_tokens is Number(_) {
    config["maxOutputTokens"] = self.max_tokens
    has_config = true
  }
  if self.temperature is Number(_) {
    config["temperature"] = self.temperature
    has_config = true
  }
  if self.top_p is Number(_) {
    config["topP"] = self.top_p
    has_config = true
  }
  if self.top_k is Number(_) {
    config["topK"] = self.top_k
    has_config = true
  }
  if self.stop is Array(_) {
    config["stopSequences"] = self.stop
    has_config = true
  }
  if has_config {
    obj["generationConfig"] = Json::object(config)
  }
}
