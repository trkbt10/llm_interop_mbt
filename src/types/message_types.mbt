///|
/// Tool call kind
pub(all) enum ToolCallKind {
  Function
  WebSearch
} derive(Show, Eq)

///|
/// Output text annotation
pub(all) enum ResponseAnnotation {
  UrlCitation(
    title~ : String?,
    url~ : String,
    start_index~ : Int,
    end_index~ : Int
  )
} derive(Show, Eq)

///|
/// Tool call status
pub(all) enum ToolCallStatus {
  InProgress
  Searching
  Completed
} derive(Show, Eq)

///|
/// Tool call trace metadata
pub(all) struct ToolCallTrace {
  id : String
  name : String
  kind : ToolCallKind
  statuses : Array[ToolCallStatus]
  arguments : Json
}

///|
/// Rich text response metadata
pub(all) struct RichTextResponse {
  content : String
  annotations : Array[ResponseAnnotation]
  tool_traces : Array[ToolCallTrace]
}

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
  /// Tool call kind
  kind : ToolCallKind
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
  /// Text response with annotations or tool traces
  RichText(RichTextResponse)
  /// Tool call request
  ToolCalls(Array[ToolCallRequest])
  /// Error
  ModelError(String)
  /// Rate limited
  RateLimited(retry_after~ : Int)
}
