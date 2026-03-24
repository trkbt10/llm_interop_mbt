///|
/// Tool call accumulator whitebox tests

///|
test "process_tool_call_delta falls back to the last accumulated call" {
  let tool_calls : Array[ToolCallAcc] = [
    { id: "fc_001", name: "", arguments: StringBuilder::new() },
  ]
  process_tool_call_delta(tool_calls, { "function": { "name": "search" } })
  assert_eq(tool_calls.length(), 1)
  assert_eq(tool_calls[0].id, "fc_001")
  assert_eq(tool_calls[0].name, "search")
  assert_eq(tool_calls[0].arguments.to_string(), "")
}

///|
test "process_tool_call_delta ignores negative index" {
  let tool_calls : Array[ToolCallAcc] = []
  process_tool_call_delta(tool_calls, {
    "index": -1,
    "function": { "name": "ignored", "arguments": "{\"q\":\"x\"}" },
  })
  assert_eq(tool_calls.length(), 0)
}

///|
test "process_tool_call_delta grows array for sparse index and appends args" {
  let tool_calls : Array[ToolCallAcc] = []
  process_tool_call_delta(tool_calls, {
    "index": 2,
    "id": "fc_sparse",
    "function": { "name": "lookup", "arguments": "{\"topic\":\"MoonBit\"}" },
  })
  assert_eq(tool_calls.length(), 3)
  assert_eq(tool_calls[2].id, "fc_sparse")
  assert_eq(tool_calls[2].name, "lookup")
  assert_true(tool_calls[2].arguments.to_string().contains("MoonBit"))
}

///|
test "tool_calls_to_requests converts validated accumulators" {
  let args = StringBuilder::new()
  args.write_string("{\"topic\":\"MoonBit\"}")
  let calls = tool_calls_to_requests([
    { id: "fc_valid", name: "lookup", arguments: args },
  ])
  assert_eq(calls.length(), 1)
  assert_eq(calls[0].id, "fc_valid")
  assert_eq(calls[0].name, "lookup")
  assert_eq(calls[0].arguments, { "topic": "MoonBit" })
}

///|
test "panic tool_calls_to_requests rejects missing ids" {
  let args = StringBuilder::new()
  args.write_string("{}")
  tool_calls_to_requests([{ id: "", name: "lookup", arguments: args }])
  |> ignore
}

///|
test "panic tool_calls_to_requests rejects missing names" {
  let args = StringBuilder::new()
  args.write_string("{}")
  tool_calls_to_requests([{ id: "fc_valid", name: "", arguments: args }])
  |> ignore
}

///|
test "panic tool_calls_to_requests rejects malformed arguments" {
  let args = StringBuilder::new()
  args.write_string("{")
  tool_calls_to_requests([{ id: "fc_valid", name: "lookup", arguments: args }])
  |> ignore
}
