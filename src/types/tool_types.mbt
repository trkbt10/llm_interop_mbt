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
