///|
/// Tool kind
pub(all) enum ToolDefinitionKind {
  Function
  WebSearchPreview(
    search_context_size~ : String?,
    user_location_country~ : String?
  )
  WebSearchPreview20250311(
    search_context_size~ : String?,
    user_location_country~ : String?
  )
} derive(Show, Eq)

///|
/// Tool-related types

///|
/// Tool parameter type enumeration
pub(all) enum ToolParamType {
  String_
  Number
  Integer
  Boolean
  Array_(ToolParamType)
  Object(Map[String, ToolParamType])
}

///|
/// Tool parameter definition
pub(all) struct ToolParam {
  /// Parameter name
  name : String
  /// Description
  description : String
  /// Type
  param_type : ToolParamType
  /// Whether required
  required : Bool
  /// Default value
  default_value : Json?
}

///|
/// Tool definition (format sent to models)
pub(all) struct ToolDefinition {
  /// Tool kind
  kind : ToolDefinitionKind
  /// Tool name
  name : String
  /// Description
  description : String
  /// Parameter definition (JSON Schema format)
  parameters : Json
  /// JSON Schema for validation (optional)
  schema : Json?
  /// Plugin metadata
  metadata : Map[String, String]
}

// =============================================================================
// Web Search Tool: shared definition (SoT)
// Each dialect wraps this in its native format.
// =============================================================================

///|
pub fn web_search_tool_name() -> String {
  "web_search"
}

///|
pub fn web_search_tool_description() -> String {
  "Search the web"
}

///|
/// JSON Schema for web search tool parameters (shared across all dialects)
pub fn web_search_tool_parameters_schema() -> Json {
  {
    "type": "object",
    "properties": { "query": { "type": "string" } },
    "required": Json::array([Json::string("query")]),
  }
}

///|
/// Build a web search action JSON from tool input/arguments.
/// Used by to_responses transforms across dialects.
pub fn build_web_search_action(input : Json) -> Json {
  let action : Map[String, Json] = { "type": Json::string("search") }
  match input {
    { "query": String(query), .. } => action["query"] = Json::string(query)
    _ => ()
  }
  match input {
    { "queries": Array(queries), .. } =>
      action["queries"] = Json::array(queries)
    _ => ()
  }
  Json::object(action)
}

///|
/// Parameter type enum (simplified)
pub(all) enum ParameterType {
  String
  Number
  Boolean
  Object
  Array
}

///|
/// Tool parameter definition (simplified)
pub(all) struct ToolParameter {
  /// Parameter name
  name : String
  /// Parameter type
  param_type : ParameterType
  /// Parameter description
  description : String
  /// Whether required
  required : Bool
}
