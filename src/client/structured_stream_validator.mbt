///|
/// Incremental validator for structured-output streaming.
///
/// The validator only activates for `json_object` / `json_schema` response
/// formats. It performs:
/// - Prefix JSON validation on every `response.output_text.delta`
/// - Final JSON completion checks on `response.output_text.done/completed`
/// - Schema validation once the buffered text becomes a complete JSON value

///|
priv struct StructuredStreamValidator {
  format : @types.ResponseFormat?
  text : StringBuilder
  mut saw_text : Bool
}

///|
fn StructuredStreamValidator::new(
  format : @types.ResponseFormat?,
) -> StructuredStreamValidator {
  { format, text: StringBuilder::new(), saw_text: false }
}

///|
fn StructuredStreamValidator::feed(
  self : StructuredStreamValidator,
  event_type : String,
  event_data : Json,
) -> Unit raise ClientError {
  guard should_validate_structured_stream(self.format) else { return }
  match event_type {
    "response.output_text.delta" =>
      match event_data {
        { "delta": String(delta), .. } => {
          self.record_text_delta(delta)
          self.validate_current(false)
        }
        _ => ()
      }
    "response.output_text.done" =>
      match event_data {
        { "text": String(text), .. } => {
          self.replace_with_final_text(text)
          self.validate_current(true)
        }
        _ => if self.saw_text { self.validate_current(true) }
      }
    "response.completed" => self.finish()
    _ => ()
  }
}

///|
fn StructuredStreamValidator::finish(
  self : StructuredStreamValidator,
) -> Unit raise ClientError {
  guard should_validate_structured_stream(self.format) else { return }
  guard self.saw_text else { return }
  self.validate_current(true)
}

///|
fn StructuredStreamValidator::record_text_delta(
  self : StructuredStreamValidator,
  delta : String,
) -> Unit {
  if delta.length() > 0 {
    self.saw_text = true
    self.text.write_string(delta)
  }
}

///|
fn StructuredStreamValidator::replace_with_final_text(
  self : StructuredStreamValidator,
  text : String,
) -> Unit {
  self.saw_text = true
  if self.text.to_string() != text {
    self.text.reset()
    self.text.write_string(text)
  }
}

///|
fn StructuredStreamValidator::validate_current(
  self : StructuredStreamValidator,
  is_complete : Bool,
) -> Unit raise ClientError {
  let current = self.text.to_string()
  if current.trim().length() == 0 {
    if is_complete && self.saw_text {
      raise ClientError::ParseError(
        "Structured output stream ended without JSON content",
      )
    }
    return
  }
  try @json.parse(current) catch {
    err =>
      match err {
        @json.InvalidEof =>
          if is_complete {
            raise ClientError::ParseError(
              "Structured output stream ended before a complete JSON value was produced",
            )
          }
        _ =>
          raise ClientError::ParseError(
            "Structured output stream is not valid JSON: " + err.to_string(),
          )
      }
  } noraise {
    value => self.validate_json_value(value)
  }
}

///|
fn StructuredStreamValidator::validate_json_value(
  self : StructuredStreamValidator,
  value : Json,
) -> Unit raise ClientError {
  match self.format {
    Some(@types.ResponseFormat::JsonObject) =>
      match value {
        Object(_) => ()
        _ =>
          raise ClientError::ParseError(
            "Structured output must be a JSON object",
          )
      }
    Some(@types.ResponseFormat::JsonSchema(schema~, ..)) =>
      match schema_validation_error(value, schema, "$") {
        Some(message) =>
          raise ClientError::ParseError(
            "Structured output does not match response schema: " + message,
          )
        None => ()
      }
    _ => ()
  }
}

///|
fn should_validate_structured_stream(format : @types.ResponseFormat?) -> Bool {
  match format {
    Some(@types.ResponseFormat::JsonObject) => true
    Some(@types.ResponseFormat::JsonSchema(..)) => true
    _ => false
  }
}

///|
fn schema_validation_error(
  value : Json,
  schema : Json,
  path : String,
) -> String? {
  match schema {
    Object(fields) => {
      match validate_all_of(value, fields, path) {
        Some(err) => return Some(err)
        None => ()
      }
      match validate_any_of(value, fields, path) {
        Some(err) => return Some(err)
        None => ()
      }
      match validate_one_of(value, fields, path) {
        Some(err) => return Some(err)
        None => ()
      }
      match validate_const_and_enum(value, fields, path) {
        Some(err) => return Some(err)
        None => ()
      }
      match validate_type_constraint(value, fields, path) {
        Some(err) => return Some(err)
        None => ()
      }
      match value {
        Object(obj) =>
          match validate_object_keywords(obj, fields, path) {
            Some(err) => return Some(err)
            None => ()
          }
        Array(items) =>
          match validate_array_keywords(items, fields, path) {
            Some(err) => return Some(err)
            None => ()
          }
        String(text) =>
          match validate_string_keywords(text, fields, path) {
            Some(err) => return Some(err)
            None => ()
          }
        Number(number, ..) =>
          match validate_number_keywords(number, fields, path) {
            Some(err) => return Some(err)
            None => ()
          }
        _ => ()
      }
      None
    }
    _ => None
  }
}

///|
fn validate_all_of(
  value : Json,
  fields : Map[String, Json],
  path : String,
) -> String? {
  match fields.get("allOf") {
    Some(Array(schemas)) =>
      for schema in schemas {
        match schema_validation_error(value, schema, path) {
          Some(err) => return Some(err)
          None => ()
        }
      }
    _ => ()
  }
  None
}

///|
fn validate_any_of(
  value : Json,
  fields : Map[String, Json],
  path : String,
) -> String? {
  match fields.get("anyOf") {
    Some(Array(schemas)) => {
      let mut matched = false
      for schema in schemas {
        match schema_validation_error(value, schema, path) {
          None => matched = true
          Some(_) => ()
        }
      }
      if not(matched) {
        return Some(path + " does not match any allowed schema")
      }
    }
    _ => ()
  }
  None
}

///|
fn validate_one_of(
  value : Json,
  fields : Map[String, Json],
  path : String,
) -> String? {
  match fields.get("oneOf") {
    Some(Array(schemas)) => {
      let mut matches = 0
      for schema in schemas {
        match schema_validation_error(value, schema, path) {
          None => matches += 1
          Some(_) => ()
        }
      }
      if matches != 1 {
        return Some(path + " must match exactly one schema")
      }
    }
    _ => ()
  }
  None
}

///|
fn validate_const_and_enum(
  value : Json,
  fields : Map[String, Json],
  path : String,
) -> String? {
  match fields.get("const") {
    Some(expected) if value != expected =>
      return Some(path + " must equal " + expected.stringify())
    _ => ()
  }
  match fields.get("enum") {
    Some(Array(variants)) => {
      let mut matched = false
      for variant in variants {
        if variant == value {
          matched = true
        }
      }
      if not(matched) {
        return Some(path + " must match one of the enum values")
      }
    }
    _ => ()
  }
  None
}

///|
fn validate_type_constraint(
  value : Json,
  fields : Map[String, Json],
  path : String,
) -> String? {
  match fields.get("type") {
    Some(String(type_name)) =>
      if not(matches_json_schema_type(value, type_name)) {
        return Some(
          path +
          " must be " +
          type_name +
          ", got " +
          json_value_type_name(value),
        )
      }
    Some(Array(type_names)) => {
      let mut matched = false
      let allowed : Array[String] = []
      for type_name in type_names {
        match type_name {
          String(name) => {
            allowed.push(name)
            if matches_json_schema_type(value, name) {
              matched = true
            }
          }
          _ => ()
        }
      }
      if allowed.length() > 0 && not(matched) {
        return Some(
          path +
          " must be one of [" +
          allowed.join(", ") +
          "], got " +
          json_value_type_name(value),
        )
      }
    }
    _ => ()
  }
  None
}

///|
fn validate_object_keywords(
  obj : Map[String, Json],
  fields : Map[String, Json],
  path : String,
) -> String? {
  match fields.get("required") {
    Some(Array(required)) =>
      for required_key in required {
        match required_key {
          String(name) =>
            if not(obj.contains(name)) {
              return Some(path + " is missing required property `" + name + "`")
            }
          _ => ()
        }
      }
    _ => ()
  }
  let props = match fields.get("properties") {
    Some(Object(props)) => Some(props)
    _ => None
  }
  match props {
    Some(properties) =>
      for key, prop_schema in properties {
        match obj.get(key) {
          Some(prop_value) =>
            match
              schema_validation_error(prop_value, prop_schema, path + "." + key) {
              Some(err) => return Some(err)
              None => ()
            }
          None => ()
        }
      }
    None => ()
  }
  match fields.get("additionalProperties") {
    Some(False) =>
      for key, _ in obj {
        let allowed = match props {
          Some(properties) => properties.contains(key)
          None => false
        }
        if not(allowed) {
          return Some(path + " contains unsupported property `" + key + "`")
        }
      }
    Some(Object(extra_schema)) =>
      for key, prop_value in obj {
        let allowed = match props {
          Some(properties) => properties.contains(key)
          None => false
        }
        if not(allowed) {
          match
            schema_validation_error(
              prop_value,
              Json::object(extra_schema),
              path + "." + key,
            ) {
            Some(err) => return Some(err)
            None => ()
          }
        }
      }
    _ => ()
  }
  None
}

///|
fn validate_array_keywords(
  items : Array[Json],
  fields : Map[String, Json],
  path : String,
) -> String? {
  match fields.get("minItems") {
    Some(Number(min_items, ..)) =>
      if items.length().to_double() < min_items {
        return Some(
          path + " must contain at least " + min_items.to_string() + " items",
        )
      }
    _ => ()
  }
  match fields.get("maxItems") {
    Some(Number(max_items, ..)) =>
      if items.length().to_double() > max_items {
        return Some(
          path + " must contain at most " + max_items.to_string() + " items",
        )
      }
    _ => ()
  }
  match fields.get("items") {
    Some(item_schema) =>
      for index, item in items {
        match
          schema_validation_error(
            item,
            item_schema,
            path + "[" + index.to_string() + "]",
          ) {
          Some(err) => return Some(err)
          None => ()
        }
      }
    _ => ()
  }
  None
}

///|
fn validate_string_keywords(
  text : String,
  fields : Map[String, Json],
  path : String,
) -> String? {
  match fields.get("minLength") {
    Some(Number(min_length, ..)) =>
      if text.char_length().to_double() < min_length {
        return Some(
          path + " must be at least " + min_length.to_string() + " characters",
        )
      }
    _ => ()
  }
  match fields.get("maxLength") {
    Some(Number(max_length, ..)) =>
      if text.char_length().to_double() > max_length {
        return Some(
          path + " must be at most " + max_length.to_string() + " characters",
        )
      }
    _ => ()
  }
  match fields.get("format") {
    Some(String("uri")) =>
      if not(looks_like_uri(text)) {
        return Some(path + " must be a valid uri")
      }
    Some(String("email")) =>
      if not(looks_like_email(text)) {
        return Some(path + " must be a valid email")
      }
    Some(String("date")) =>
      if not(looks_like_date(text)) {
        return Some(path + " must be a valid date")
      }
    _ => ()
  }
  None
}

///|
fn validate_number_keywords(
  number : Double,
  fields : Map[String, Json],
  path : String,
) -> String? {
  match fields.get("minimum") {
    Some(Number(minimum, ..)) =>
      if number < minimum {
        return Some(path + " must be >= " + minimum.to_string())
      }
    _ => ()
  }
  match fields.get("maximum") {
    Some(Number(maximum, ..)) =>
      if number > maximum {
        return Some(path + " must be <= " + maximum.to_string())
      }
    _ => ()
  }
  match fields.get("exclusiveMinimum") {
    Some(Number(minimum, ..)) =>
      if number <= minimum {
        return Some(path + " must be > " + minimum.to_string())
      }
    _ => ()
  }
  match fields.get("exclusiveMaximum") {
    Some(Number(maximum, ..)) =>
      if number >= maximum {
        return Some(path + " must be < " + maximum.to_string())
      }
    _ => ()
  }
  None
}

///|
fn matches_json_schema_type(value : Json, type_name : String) -> Bool {
  match type_name {
    "null" =>
      match value {
        Null => true
        _ => false
      }
    "boolean" => matches_json_boolean(value)
    "number" =>
      match value {
        Number(_, ..) => true
        _ => false
      }
    "integer" => matches_json_integer(value)
    "string" =>
      match value {
        String(_) => true
        _ => false
      }
    "array" =>
      match value {
        Array(_) => true
        _ => false
      }
    "object" =>
      match value {
        Object(_) => true
        _ => false
      }
    _ => false
  }
}

///|
fn matches_json_boolean(value : Json) -> Bool {
  match value {
    True | False => true
    _ => false
  }
}

///|
fn matches_json_integer(value : Json) -> Bool {
  match value {
    Number(number, ..) => number.to_int().to_double() == number
    _ => false
  }
}

///|
fn json_value_type_name(value : Json) -> String {
  match value {
    Null => "null"
    True | False => "boolean"
    Number(number, ..) =>
      if number.to_int().to_double() == number {
        "integer"
      } else {
        "number"
      }
    String(_) => "string"
    Array(_) => "array"
    Object(_) => "object"
  }
}

///|
fn looks_like_uri(text : String) -> Bool {
  let parts = text.split("://").map(StringView::to_string).collect()
  if parts.length() == 2 && parts[0].length() > 0 && parts[1].length() > 0 {
    return true
  }
  text.contains("urn:")
}

///|
fn looks_like_email(text : String) -> Bool {
  let parts = text.split("@").map(StringView::to_string).collect()
  if parts.length() != 2 {
    return false
  }
  let user = parts[0]
  let domain = parts[1]
  user.length() > 0 && domain.length() > 0 && domain.contains(".")
}

///|
fn looks_like_date(text : String) -> Bool {
  let parts = text.split("-").map(StringView::to_string).collect()
  if parts.length() != 3 {
    return false
  }
  parts[0].length() == 4 && parts[1].length() == 2 && parts[2].length() == 2
}
