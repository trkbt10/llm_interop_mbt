///|
/// SSE serializer tests

///|
test "format_sse_event produces correct wire format" {
  let result = format_sse_event("response.created", {
    "type": "response.created",
  })
  let expected =
    #|event: response.created
    #|data: {"type":"response.created"}
    #|
    #|
  inspect(result, content=expected)
}

///|
test "format_sse_done produces correct wire format" {
  let result = format_sse_done()
  let expected =
    #|data: [DONE]
    #|
    #|
  inspect(result, content=expected)
}

///|
test "format_sse_event round-trip with parse_sse_chunk" {
  let event_type = "response.output_text.delta"
  let data : Json = { "type": "response.output_text.delta", "delta": "Hello" }
  let wire = format_sse_event(event_type, data)
  let parsed = parse_sse_chunk(wire)
  inspect(parsed.events.length(), content="1")
  inspect(parsed.events[0].event, content="response.output_text.delta")
  inspect(parsed.remaining, content="")
  // Verify data round-trips
  match parsed.events[0].data {
    { "delta": String(d), .. } => inspect(d, content="Hello")
    _ => fail("expected delta field")
  }
}

///|
test "format_sse_event round-trip with nested JSON" {
  let event_type = "response.output_item.added"
  let data : Json = {
    "type": "response.output_item.added",
    "output_index": 0,
    "item": { "id": "msg_001", "type": "message", "role": "assistant" },
  }
  let wire = format_sse_event(event_type, data)
  let parsed = parse_sse_chunk(wire)
  inspect(parsed.events.length(), content="1")
  inspect(parsed.events[0].event, content="response.output_item.added")
  match parsed.events[0].data {
    { "item": { "id": String(id), .. }, .. } => inspect(id, content="msg_001")
    _ => fail("expected nested item.id")
  }
}

///|
test "multiple format_sse_event concatenated parse correctly" {
  let wire = format_sse_event("response.created", { "type": "response.created" }) +
    format_sse_event("response.output_text.delta", {
      "type": "response.output_text.delta",
      "delta": "Hi",
    })
  let parsed = parse_sse_chunk(wire)
  inspect(parsed.events.length(), content="2")
  inspect(parsed.events[0].event, content="response.created")
  inspect(parsed.events[1].event, content="response.output_text.delta")
}
