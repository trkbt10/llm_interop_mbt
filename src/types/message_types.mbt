///|
/// Message-related types

///|
/// Tool call request
pub(all) struct ToolCallRequest {
  /// Call ID
  id : String
  /// Tool name
  name : String
  /// Arguments (JSON format)
  arguments : Json
}

///|
/// Message sent to model
pub(all) enum ModelMessage {
  /// System message
  System(String)
  /// User message
  User(content~ : String, name~ : String?)
  /// Assistant message
  Assistant(content~ : String, tool_calls~ : Array[ToolCallRequest]?)
  /// Tool execution result
  ToolResult(tool_call_id~ : String, content~ : String)
}

///|
/// Tool execution result
pub(all) enum ToolResult {
  /// Success
  Success(content~ : String)
  /// Error
  Error(message~ : String)
  /// Requires additional tool call
  RequiresAction(next_tool~ : String, arguments~ : Json)
}

///|
/// Model response
pub(all) enum ModelResponse {
  /// Text response
  Text(String)
  /// Tool call request
  ToolCalls(Array[ToolCallRequest])
  /// Error
  ModelError(String)
  /// Rate limited
  RateLimited(retry_after~ : Int)
}
