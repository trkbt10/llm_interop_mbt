///|
/// SSE types

///|
/// SSE event (parsed from JSONL)
pub(all) struct SseEvent {
  /// Event name (empty string for Chat Completions)
  event : String
  /// Data payload
  data : Json
}

///|
/// Tool call accumulation internal structure
struct ToolCallAcc {
  id : String
  name : String
  arguments : StringBuilder
}
