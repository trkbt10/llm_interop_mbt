///|
/// JSON Schema normalizer for OpenAI structured-output compatibility.
///
/// OpenAI strict mode requires a narrower schema subset than generic JSON
/// Schema. This helper keeps the normalization logic in the shared types
/// package so every OpenAI-targeting bridge uses the same rules.

///|
/// Normalize a JSON Schema for OpenAI strict mode compatibility.
/// - Adds all object property names to `required`
/// - Removes `format: "uri"`
/// - Sets `additionalProperties: false` on object schemas
pub fn normalize_json_schema_for_openai(schema : Json) -> Json {
  normalize_schema_recursive(schema)
}

///|
/// Normalize a JSON Schema for Anthropic structured-output compatibility.
/// Anthropic currently requires object schemas to set
/// `additionalProperties: false`, but supports generic JSON Schema `format`
/// values such as `uri`, so this normalizer preserves formats.
fn normalize_json_schema_for_anthropic(schema : Json) -> Json {
  normalize_schema_recursive_for_anthropic(schema)
}

///|
/// Recursively normalize a schema.
fn normalize_schema_recursive(schema : Json) -> Json {
  match schema {
    Object(map) => {
      let result : Map[String, Json] = {}
      for key, value in map {
        result[key] = value
      }
      let is_object = match result.get("type") {
        Some(String("object")) => true
        _ => false
      }
      match result.get("properties") {
        Some(Object(props)) => {
          let normalized_props : Map[String, Json] = {}
          let prop_names : Array[String] = []
          for name, prop_schema in props {
            prop_names.push(name)
            normalized_props[name] = normalize_schema_recursive(prop_schema)
          }
          result["properties"] = Json::object(normalized_props)
          if is_object && prop_names.length() > 0 {
            result["required"] = Json::array(
              prop_names.map(fn(name) { Json::string(name) }),
            )
          }
        }
        _ => ()
      }
      if is_object {
        result["additionalProperties"] = Json::boolean(false)
      }
      match result.get("items") {
        Some(items) => result["items"] = normalize_schema_recursive(items)
        _ => ()
      }
      match result.get("format") {
        Some(String("uri")) => {
          let _ = result.remove("format")
        }
        _ => ()
      }
      Json::object(result)
    }
    Array(items) => Json::array(items.map(normalize_schema_recursive))
    _ => schema
  }
}

///|
fn normalize_schema_recursive_for_anthropic(schema : Json) -> Json {
  match schema {
    Object(map) => {
      let result : Map[String, Json] = {}
      for key, value in map {
        result[key] = value
      }
      let is_object = match result.get("type") {
        Some(String("object")) => true
        _ => false
      }
      match result.get("properties") {
        Some(Object(props)) => {
          let normalized_props : Map[String, Json] = {}
          for name, prop_schema in props {
            normalized_props[name] = normalize_schema_recursive_for_anthropic(
              prop_schema,
            )
          }
          result["properties"] = Json::object(normalized_props)
        }
        _ => ()
      }
      if is_object {
        result["additionalProperties"] = Json::boolean(false)
      }
      match result.get("items") {
        Some(items) =>
          result["items"] = normalize_schema_recursive_for_anthropic(items)
        _ => ()
      }
      Json::object(result)
    }
    Array(items) =>
      Json::array(items.map(normalize_schema_recursive_for_anthropic))
    _ => schema
  }
}

///|
/// Check if a schema needs OpenAI strict-mode normalization.
pub fn schema_needs_normalization(schema : Json) -> Bool {
  check_needs_normalization_recursive(schema)
}

///|
fn check_needs_normalization_recursive(schema : Json) -> Bool {
  match schema {
    Object(map) => {
      let is_object = match map.get("type") {
        Some(String("object")) => true
        _ => false
      }
      if is_object {
        match map.get("additionalProperties") {
          Some(False) => ()
          _ => return true
        }
      }
      match map.get("format") {
        Some(String("uri")) => return true
        _ => ()
      }
      match (map.get("properties"), map.get("required")) {
        (Some(Object(props)), None) => if props.length() > 0 { return true }
        (Some(Object(props)), Some(Array(req))) =>
          if props.length() != req.length() {
            return true
          }
        _ => ()
      }
      match map.get("properties") {
        Some(Object(props)) =>
          for _, prop_schema in props {
            if check_needs_normalization_recursive(prop_schema) {
              return true
            }
          }
        _ => ()
      }
      match map.get("items") {
        Some(items) =>
          if check_needs_normalization_recursive(items) {
            return true
          }
        _ => ()
      }
      false
    }
    _ => false
  }
}
