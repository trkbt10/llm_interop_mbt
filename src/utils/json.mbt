///|
/// Set or update a field in a JSON object
pub fn set_json_field(json : Json, key : String, value : Json) -> Json {
  match json {
    Object(map) => {
      map[key] = value
      Json::object(map)
    }
    _ => json
  }
}

///|
/// Extract a string field from a JSON body
pub fn extract_json_field(body : String, field : String) -> String? {
  let json = @json.parse(body) catch { _ => return None }
  match json {
    Object(obj) =>
      match obj.get(field) {
        Some(String(v)) => Some(v)
        _ => None
      }
    _ => None
  }
}

///|
/// Inject a string field into JSON body if not already present
pub fn inject_json_field(
  body : String,
  field : String,
  value : String,
) -> String {
  let json = @json.parse(body) catch { _ => return body }
  match json {
    Object(obj) =>
      match obj.get(field) {
        Some(_) => body
        None => {
          obj[field] = Json::string(value)
          Json::object(obj).stringify()
        }
      }
    _ => body
  }
}

///|
/// Parse a Responses API function tool definition.
/// Missing description/parameters are normalized to empty values.
pub fn parse_responses_function_tool(tool : Json) -> (String, String, Json)? {
  match tool {
    { "type": String("function"), "name": String(name), .. } => {
      let description = match tool {
        { "description": String(d), .. } => d
        _ => ""
      }
      let parameters = match tool {
        { "parameters": params, .. } => params
        _ => Json::object({})
      }
      Some((name, description, parameters))
    }
    _ => None
  }
}

///|
/// Extract the optional display name from a Responses tool object.
pub fn extract_responses_tool_name(tool : Json) -> String {
  match tool {
    { "name": String(name), .. } => name
    _ => ""
  }
}

///|
/// Extract builtin tool config from a Responses tool object by removing the
/// common tool envelope fields.
pub fn extract_responses_tool_config(tool : Json) -> Json {
  match tool {
    Object(fields) => {
      let config : Map[String, Json] = {}
      for key, value in fields {
        if key != "type" &&
          key != "name" &&
          key != "description" &&
          key != "parameters" {
          config[key] = value
        }
      }
      Json::object(config)
    }
    _ => Json::object({})
  }
}
