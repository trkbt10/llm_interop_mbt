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

