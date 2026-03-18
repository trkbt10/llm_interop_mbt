///|
/// SSE serializer — formats events for Server-Sent Events wire protocol

///|
/// Format an SSE event with event type and JSON data payload
/// Returns: "event: {event_type}\ndata: {json}\n\n"
pub fn format_sse_event(event_type : String, data : Json) -> String {
  "event: " + event_type + "\ndata: " + data.stringify() + "\n\n"
}

///|
/// Format the SSE stream termination marker
/// Returns: "data: [DONE]\n\n"
pub fn format_sse_done() -> String {
  "data: [DONE]\n\n"
}
