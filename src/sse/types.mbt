///|
/// SSE types

///|
/// SSE event (parsed from JSONL)
pub(all) struct SseEvent {
  /// Event name (empty string for data-only format)
  event : String
  /// Data payload
  data : Json
}
