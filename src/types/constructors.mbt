///|
/// Constructors and helpers

///|
/// Create default ToolCallRequest
pub fn ToolCallRequest::default() -> ToolCallRequest {
  { id: "", name: "", arguments: Json::null() }
}

///|
/// Create new ToolCallRequest
pub fn ToolCallRequest::new(
  id~ : String,
  name~ : String,
  arguments~ : Json,
) -> ToolCallRequest {
  { id, name, arguments }
}

///|
/// Create new ToolDefinition
pub fn ToolDefinition::new(
  name~ : String,
  description~ : String,
  parameters~ : Json,
) -> ToolDefinition {
  { name, description, parameters, schema: None, metadata: {} }
}

///|
/// Build JSON Schema helper
pub fn build_json_schema(
  type_~ : String,
  properties~ : Map[String, Json],
  required~ : Array[String],
) -> Json {
  {
    "type": type_,
    "properties": Json::object(properties),
    "required": Json::array(required.map(fn(s) { Json::string(s) })),
  }
}
