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
