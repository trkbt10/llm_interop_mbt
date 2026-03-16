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
pub fn inject_json_field(body : String, field : String, value : String) -> String {
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
