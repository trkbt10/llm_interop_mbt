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
  response_format : ResponseFormat?
  response_format_context : ResponseFormatContext?
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
    response_format: None,
    response_format_context: None,
  }
}

///|
fn object_string_field(json : Json, key : String) -> String? {
  match json {
    Object(fields) =>
      match fields.get(key) {
        Some(String(value)) => Some(value)
        _ => None
      }
    _ => None
  }
}

///|
fn object_bool_field(json : Json, key : String) -> Bool? {
  match json {
    Object(fields) =>
      match fields.get(key) {
        Some(True) => Some(true)
        Some(False) => Some(false)
        _ => None
      }
    _ => None
  }
}

///|
fn object_json_field(json : Json, key : String) -> Json? {
  match json {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
fn parse_openai_json_schema_config(config : Json) -> ResponseFormat? {
  match object_json_field(config, "schema") {
    Some(schema) =>
      Some(
        ResponseFormat::JsonSchema(
          name=object_string_field(config, "name"),
          schema~,
          description=object_string_field(config, "description"),
          strict=object_bool_field(config, "strict"),
        ),
      )
    None => None
  }
}

///|
fn parse_openai_chat_response_format(format : Json) -> ResponseFormat? {
  match object_string_field(format, "type") {
    Some("text") => Some(ResponseFormat::Text)
    Some("json_object") => Some(ResponseFormat::JsonObject)
    Some("json_schema") =>
      match object_json_field(format, "json_schema") {
        Some(config) => parse_openai_json_schema_config(config)
        None => None
      }
    _ => None
  }
}

///|
fn parse_openai_responses_text_format(format : Json) -> ResponseFormat? {
  match object_string_field(format, "type") {
    Some("text") => Some(ResponseFormat::Text)
    Some("json_object") => Some(ResponseFormat::JsonObject)
    Some("json_schema") => parse_openai_json_schema_config(format)
    _ => None
  }
}

///|
fn parse_anthropic_response_format(format : Json) -> ResponseFormat? {
  match
    (object_string_field(format, "type"), object_json_field(format, "schema")) {
    (Some("json_schema"), Some(schema)) =>
      Some(
        ResponseFormat::JsonSchema(
          name=None,
          schema~,
          description=None,
          strict=None,
        ),
      )
    _ => None
  }
}

///|
fn parse_gemini_response_format(config : Json) -> ResponseFormat? {
  match object_json_field(config, "responseJsonSchema") {
    Some(schema) =>
      return Some(
        ResponseFormat::JsonSchema(
          name=None,
          schema~,
          description=None,
          strict=None,
        ),
      )
    None => ()
  }
  match object_json_field(config, "responseSchema") {
    Some(schema) =>
      return Some(
        ResponseFormat::JsonSchema(
          name=None,
          schema~,
          description=None,
          strict=None,
        ),
      )
    None => ()
  }
  match object_string_field(config, "responseMimeType") {
    Some("application/json") => Some(ResponseFormat::JsonObject)
    Some("text/plain") => Some(ResponseFormat::Text)
    _ => None
  }
}

///|
fn openai_response_format_name(name : String?) -> String {
  match name {
    Some(value) if value.length() > 0 => value
    _ => "response"
  }
}

///|
fn response_format_context(
  surface : String,
  raw : Json,
) -> ResponseFormatContext {
  { surface, raw }
}

///|
fn normalized_openai_schema(schema : Json, strict : Bool?) -> Json {
  match strict {
    Some(true) => normalize_json_schema_for_openai(schema)
    _ => schema
  }
}

///|
fn build_openai_chat_response_format(format : ResponseFormat) -> Json {
  match format {
    ResponseFormat::Text => { "type": "text" }
    ResponseFormat::JsonObject => { "type": "json_object" }
    ResponseFormat::JsonSchema(name~, schema~, description~, strict~) => {
      let schema = normalized_openai_schema(schema, strict)
      let config : Map[String, Json] = {
        "name": Json::string(openai_response_format_name(name)),
        "schema": schema,
      }
      match description {
        Some(value) => config["description"] = Json::string(value)
        None => ()
      }
      match strict {
        Some(value) => config["strict"] = Json::boolean(value)
        None => ()
      }
      { "type": "json_schema", "json_schema": Json::object(config) }
    }
  }
}

///|
fn build_openai_responses_text_format(format : ResponseFormat) -> Json {
  match format {
    ResponseFormat::Text => { "type": "text" }
    ResponseFormat::JsonObject => { "type": "json_object" }
    ResponseFormat::JsonSchema(name~, schema~, description~, strict~) => {
      let schema = normalized_openai_schema(schema, strict)
      let config : Map[String, Json] = {
        "type": Json::string("json_schema"),
        "name": Json::string(openai_response_format_name(name)),
        "schema": schema,
      }
      match description {
        Some(value) => config["description"] = Json::string(value)
        None => ()
      }
      match strict {
        Some(value) => config["strict"] = Json::boolean(value)
        None => ()
      }
      Json::object(config)
    }
  }
}

///|
fn build_anthropic_response_format(format : ResponseFormat) -> Json? {
  match format {
    ResponseFormat::Text => None
    // Anthropic only documents json_schema. Treat json_object as the loosest
    // object schema that preserves JSON-object intent.
    ResponseFormat::JsonObject =>
      Some({
        "type": "json_schema",
        "schema": normalize_json_schema_for_anthropic({ "type": "object" }),
      })
    ResponseFormat::JsonSchema(schema~, ..) =>
      Some({
        "type": "json_schema",
        "schema": normalize_json_schema_for_anthropic(schema),
      })
  }
}

///|
fn normalize_openai_chat_response_format_json(format : Json) -> Json {
  match format {
    { "type": String("json_schema"), "json_schema": Object(config), .. } => {
      let normalized : Map[String, Json] = {}
      let strict = object_bool_field(Json::object(config), "strict")
      for key, value in config {
        if key == "schema" {
          normalized[key] = normalized_openai_schema(value, strict)
        } else {
          normalized[key] = value
        }
      }
      { "type": "json_schema", "json_schema": Json::object(normalized) }
    }
    _ => format
  }
}

///|
fn normalize_openai_responses_text_format_json(format : Json) -> Json {
  match format {
    { "type": String("json_schema"), "schema": schema, .. } => {
      let config : Map[String, Json] = {}
      let strict = object_bool_field(format, "strict")
      match format {
        Object(fields) =>
          for key, value in fields {
            if key == "schema" {
              config[key] = normalized_openai_schema(schema, strict)
            } else {
              config[key] = value
            }
          }
        _ => ()
      }
      Json::object(config)
    }
    _ => format
  }
}

///|
fn normalize_anthropic_output_config_json(raw : Json) -> Json {
  match raw {
    Object(fields) => {
      let output_config : Map[String, Json] = {}
      for key, value in fields {
        output_config[key] = value
      }
      match output_config.get("format") {
        Some(Object(format_fields)) => {
          let normalized_format : Map[String, Json] = {}
          for key, value in format_fields {
            normalized_format[key] = value
          }
          match normalized_format.get("schema") {
            Some(schema) =>
              normalized_format["schema"] = normalize_json_schema_for_anthropic(
                schema,
              )
            None => ()
          }
          output_config["format"] = Json::object(normalized_format)
        }
        _ => ()
      }
      Json::object(output_config)
    }
    _ => raw
  }
}

///|
fn response_format_context_for_surface(
  context : ResponseFormatContext?,
  surface : String,
) -> Json? {
  match context {
    Some(ctx) if ctx.surface == surface => Some(ctx.raw)
    _ => None
  }
}

///|
fn apply_gemini_response_format_context(
  config : Map[String, Json],
  context : ResponseFormatContext?,
) -> Bool {
  match response_format_context_for_surface(context, "gemini") {
    Some(Object(fields)) => {
      for key, value in fields {
        config[key] = value
      }
      true
    }
    _ => false
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
  let params = match json {
    { "response_format": format, .. } =>
      {
        ..params,
        response_format: parse_openai_chat_response_format(format),
        response_format_context: match
          parse_openai_chat_response_format(format) {
          Some(_) => Some(response_format_context("openai_chat", format))
          None => None
        },
      }
    _ => params
  }
  params
}

///|
/// Extract generation parameters from OpenAI Responses format
pub fn GenerationParams::from_responses(json : Json) -> GenerationParams {
  let params = GenerationParams::empty()
  let params = match json {
    { "max_output_tokens": Number(_) as n, .. } => { ..params, max_tokens: n }
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
    { "stream": True, .. } => { ..params, stream: Json::boolean(true) }
    { "stream": False, .. } => { ..params, stream: Json::boolean(false) }
    _ => params
  }
  let params = match json {
    { "text": { "format": format, .. }, .. } =>
      {
        ..params,
        response_format: parse_openai_responses_text_format(format),
        response_format_context: match
          parse_openai_responses_text_format(format) {
          Some(_) => Some(response_format_context("openai_responses", format))
          None => None
        },
      }
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
  let params = match json {
    { "output_config": { "format": format, .. }, .. } =>
      {
        ..params,
        response_format: parse_anthropic_response_format(format),
        response_format_context: match parse_anthropic_response_format(format) {
          Some(_) =>
            Some(response_format_context("anthropic", { "format": format }))
          None => None
        },
      }
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
  let response_format = parse_gemini_response_format(config)
  let params = {
    ..params,
    response_format,
    response_format_context: match response_format {
      Some(_) =>
        Some(
          response_format_context(
            "gemini",
            match config {
              Object(fields) => {
                let raw : Map[String, Json] = {}
                match fields.get("responseMimeType") {
                  Some(value) => raw["responseMimeType"] = value
                  None => ()
                }
                match fields.get("responseSchema") {
                  Some(value) => raw["responseSchema"] = value
                  None => ()
                }
                match fields.get("responseJsonSchema") {
                  Some(value) => raw["responseJsonSchema"] = value
                  None => ()
                }
                Json::object(raw)
              }
              _ => Json::object({})
            },
          ),
        )
      None => None
    },
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
  match self.response_format {
    Some(format) =>
      obj["response_format"] = match
        response_format_context_for_surface(
          self.response_format_context,
          "openai_chat",
        ) {
        Some(raw) => normalize_openai_chat_response_format_json(raw)
        None => build_openai_chat_response_format(format)
      }
    None => ()
  }
}

///|
/// Apply generation parameters to an OpenAI Responses request object.
pub fn GenerationParams::apply_to_responses(
  self : GenerationParams,
  obj : Map[String, Json],
) -> Unit {
  if self.max_tokens is Number(_) {
    obj["max_output_tokens"] = self.max_tokens
  }
  if self.temperature is Number(_) {
    obj["temperature"] = self.temperature
  }
  if self.top_p is Number(_) {
    obj["top_p"] = self.top_p
  }
  if self.stream is True {
    obj["stream"] = self.stream
  }
  match self.response_format {
    Some(format) =>
      obj["text"] = Json::object({
        "format": match
          response_format_context_for_surface(
            self.response_format_context,
            "openai_responses",
          ) {
          Some(raw) => normalize_openai_responses_text_format_json(raw)
          None => build_openai_responses_text_format(format)
        },
      })
    None => ()
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
  match self.response_format {
    Some(format) =>
      match
        response_format_context_for_surface(
          self.response_format_context,
          "anthropic",
        ) {
        Some(raw) =>
          obj["output_config"] = normalize_anthropic_output_config_json(raw)
        None =>
          match build_anthropic_response_format(format) {
            Some(value) => obj["output_config"] = { "format": value }
            None => ()
          }
      }
    None => ()
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
  if apply_gemini_response_format_context(config, self.response_format_context) {
    has_config = true
  } else {
    match self.response_format {
      Some(ResponseFormat::Text) => {
        config["responseMimeType"] = Json::string("text/plain")
        has_config = true
      }
      Some(ResponseFormat::JsonObject) => {
        config["responseMimeType"] = Json::string("application/json")
        has_config = true
      }
      Some(ResponseFormat::JsonSchema(schema~, ..)) => {
        config["responseMimeType"] = Json::string("application/json")
        config["responseJsonSchema"] = schema
        has_config = true
      }
      None => ()
    }
  }
  if has_config {
    obj["generationConfig"] = Json::object(config)
  }
}
