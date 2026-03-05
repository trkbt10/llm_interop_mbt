///|
/// JSON Schema normalizer for OpenAI API compatibility
///
/// Normalizes JSON Schema to meet OpenAI's strict mode requirements:
/// 1. All properties must be in the required array
/// 2. Remove uri format (OpenAI doesn't support it)
/// 3. Set additionalProperties to false for all objects

///|
/// Normalize a JSON Schema for OpenAI strict mode compatibility
/// - Adds all properties to required array for object schemas
/// - Removes uri format from string properties
/// - Sets additionalProperties to false for object schemas
pub fn normalize_json_schema_for_openai(schema : Json) -> Json {
  normalize_schema_recursive(schema)
}

///|
/// Recursively normalize a schema
fn normalize_schema_recursive(schema : Json) -> Json {
  match schema {
    Object(map) => {
      let result : Map[String, Json] = {}
      // Copy all fields first
      for k, v in map {
        result[k] = v
      }
      // Check if this is an object type schema
      let is_object = match result.get("type") {
        Some(String("object")) => true
        _ => false
      }
      // Normalize properties if present
      match result.get("properties") {
        Some(Object(props)) => {
          let normalized_props : Map[String, Json] = {}
          let prop_names : Array[String] = []
          for name, prop_schema in props {
            prop_names.push(name)
            normalized_props[name] = normalize_schema_recursive(prop_schema)
          }
          result["properties"] = Json::object(normalized_props)
          // Add all properties to required
          if is_object && prop_names.length() > 0 {
            result["required"] = Json::array(
              prop_names.map(fn(s) { Json::string(s) }),
            )
          }
        }
        _ => ()
      }
      // Set additionalProperties to false for object types
      if is_object {
        result["additionalProperties"] = Json::boolean(false)
      }
      // Normalize array items if present
      match result.get("items") {
        Some(items) => result["items"] = normalize_schema_recursive(items)
        _ => ()
      }
      // Remove uri format (OpenAI doesn't support it)
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
/// Check if a schema needs normalization
pub fn schema_needs_normalization(schema : Json) -> Bool {
  check_needs_normalization_recursive(schema)
}

///|
fn check_needs_normalization_recursive(schema : Json) -> Bool {
  match schema {
    Object(map) => {
      // Check if object type without additionalProperties: false
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
      // Check for uri format
      match map.get("format") {
        Some(String("uri")) => return true
        _ => ()
      }
      // Check if object has properties but missing required
      match (map.get("properties"), map.get("required")) {
        (Some(Object(props)), None) => if props.length() > 0 { return true }
        (Some(Object(props)), Some(Array(req))) =>
          if props.length() != req.length() {
            return true
          }
        _ => ()
      }
      // Check nested schemas
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
