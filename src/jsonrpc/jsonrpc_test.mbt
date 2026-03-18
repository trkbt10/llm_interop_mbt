///|
/// Exhaustive tests for pure JSON-RPC 2.0 protocol layer

// =============================================================================
// build_request
// =============================================================================

///|
test "build_request: basic with params" {
  let msg = build_request(1, "initialize", Some({ "key": "value" }))
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
  match json {
    { "jsonrpc": String("2.0"), "id": Number(id, ..), "method": String(m), .. } => {
      assert_eq(id.to_int(), 1)
      assert_eq(m, "initialize")
    }
    _ => fail("Invalid request format")
  }
  match json {
    { "params": { "key": String("value"), .. }, .. } => ()
    _ => fail("Missing params")
  }
}

///|
test "build_request: without params" {
  let msg = build_request(2, "test/method", None)
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
  match json {
    {
      "jsonrpc": String("2.0"),
      "id": Number(id, ..),
      "method": String("test/method"),
      ..
    } => assert_eq(id.to_int(), 2)
    _ => fail("Invalid request format")
  }
  // Should NOT have params key when None
  match json {
    { "params": _, .. } => fail("params should not be present when None")
    _ => ()
  }
}

///|
test "build_request: id zero" {
  let msg = build_request(0, "test", None)
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
  match json {
    { "id": Number(id, ..), .. } => assert_eq(id.to_int(), 0)
    _ => fail("id=0 should be present")
  }
}

///|
test "build_request: large id" {
  let msg = build_request(999999, "test", None)
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
  match json {
    { "id": Number(id, ..), .. } => assert_eq(id.to_int(), 999999)
    _ => fail("large id not preserved")
  }
}

///|
test "build_request: nested params" {
  let params : Json = { "level1": { "level2": { "level3": "deep" } } }
  let msg = build_request(1, "deep/method", Some(params))
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
  match json {
    {
      "params": {
        "level1": { "level2": { "level3": String("deep"), .. }, .. },
        ..
      },
      ..
    } => ()
    _ => fail("Nested params not preserved")
  }
}

///|
test "build_request: empty string method" {
  let msg = build_request(1, "", None)
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
  match json {
    { "method": String(m), .. } => assert_eq(m, "")
    _ => fail("Empty method not preserved")
  }
}

///|
test "build_request: method with slashes" {
  let msg = build_request(1, "tools/call", None)
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
  match json {
    { "method": String("tools/call"), .. } => ()
    _ => fail("Slashed method not preserved")
  }
}

///|
test "build_request: params with array" {
  let params : Json = {
    "items": Json::array([Json::string("a"), Json::string("b")]),
  }
  let msg = build_request(1, "test", Some(params))
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
  match json {
    { "params": { "items": Array(arr), .. }, .. } => assert_eq(arr.length(), 2)
    _ => fail("Array params not preserved")
  }
}

// =============================================================================
// build_notification
// =============================================================================

///|
test "build_notification: no params" {
  let msg = build_notification("notifications/initialized", None)
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
  match json {
    { "jsonrpc": String("2.0"), "method": String(m), .. } =>
      assert_eq(m, "notifications/initialized")
    _ => fail("Invalid notification format")
  }
  match json {
    { "id": _, .. } => fail("Notification should not have an id")
    _ => ()
  }
}

///|
test "build_notification: with params" {
  let msg = build_notification("event/update", Some({ "data": "test" }))
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
  match json {
    { "params": { "data": String("test"), .. }, .. } => ()
    _ => fail("Missing params in notification")
  }
  match json {
    { "id": _, .. } => fail("Notification should not have an id")
    _ => ()
  }
}

///|
test "build_notification: no params key when None" {
  let msg = build_notification("ping", None)
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
  match json {
    { "params": _, .. } => fail("params should not be present when None")
    _ => ()
  }
}

// =============================================================================
// build_response
// =============================================================================

///|
test "build_response: with id" {
  let msg = build_response(Some(1), { "status": "ok" })
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
  match json {
    {
      "jsonrpc": String("2.0"),
      "id": Number(id, ..),
      "result": { "status": String("ok"), .. },
      ..
    } => assert_eq(id.to_int(), 1)
    _ => fail("Invalid response format")
  }
}

///|
test "build_response: without id" {
  let msg = build_response(None, { "data": "test" })
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
  match json {
    { "jsonrpc": String("2.0"), "result": { "data": String("test"), .. }, .. } =>
      ()
    _ => fail("Invalid response format")
  }
  match json {
    { "id": _, .. } => fail("id should not be present when None")
    _ => ()
  }
}

///|
test "build_response: null result" {
  let msg = build_response(Some(1), Json::null())
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
  match json {
    { "result": Null, .. } => ()
    _ => fail("Null result not preserved")
  }
}

///|
test "build_response: array result" {
  let msg = build_response(
    Some(1),
    Json::array([Json::number(1.0), Json::number(2.0)]),
  )
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
  match json {
    { "result": Array(arr), .. } => assert_eq(arr.length(), 2)
    _ => fail("Array result not preserved")
  }
}

// =============================================================================
// build_error_response
// =============================================================================

///|
test "build_error_response: standard error" {
  let msg = build_error_response(Some(1), -32600, "Invalid Request")
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
  match json {
    {
      "jsonrpc": String("2.0"),
      "id": Number(id, ..),
      "error": { "code": Number(code, ..), "message": String(m), .. },
      ..
    } => {
      assert_eq(id.to_int(), 1)
      assert_eq(code.to_int(), -32600)
      assert_eq(m, "Invalid Request")
    }
    _ => fail("Invalid error response format")
  }
}

///|
test "build_error_response: without id" {
  let msg = build_error_response(None, -32700, "Parse error")
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
  match json {
    {
      "error": {
        "code": Number(code, ..),
        "message": String("Parse error"),
        ..
      },
      ..
    } => assert_eq(code.to_int(), -32700)
    _ => fail("Invalid error response")
  }
  match json {
    { "id": _, .. } => fail("id should not be present when None")
    _ => ()
  }
}

///|
test "build_error_response: method not found" {
  let msg = build_error_response(Some(5), -32601, "Method not found")
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
  match json {
    { "error": { "code": Number(code, ..), .. }, .. } =>
      assert_eq(code.to_int(), -32601)
    _ => fail("Invalid error response")
  }
}

// =============================================================================
// RpcRequest::from_json
// =============================================================================

///|
test "RpcRequest::from_json: full request" {
  let json : Json = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "test/method",
    "params": { "key": "value" },
  }
  match RpcRequest::from_json(json) {
    Some(r) => {
      assert_eq(r.id, Some(1))
      assert_eq(r.rpc_method, "test/method")
      assert_true(not(r.params is None))
    }
    None => fail("Failed to parse request")
  }
}

///|
test "RpcRequest::from_json: notification (no id)" {
  let json : Json = { "method": "initialized", "params": {} }
  match RpcRequest::from_json(json) {
    Some(r) => {
      assert_eq(r.id, None)
      assert_eq(r.rpc_method, "initialized")
    }
    None => fail("Failed to parse notification")
  }
}

///|
test "RpcRequest::from_json: no params" {
  let json : Json = { "jsonrpc": "2.0", "id": 3, "method": "ping" }
  match RpcRequest::from_json(json) {
    Some(r) => {
      assert_eq(r.id, Some(3))
      assert_eq(r.rpc_method, "ping")
      assert_eq(r.params, None)
    }
    None => fail("Failed to parse request without params")
  }
}

///|
test "RpcRequest::from_json: invalid (no method)" {
  assert_eq(RpcRequest::from_json({ "id": 1 }), None)
}

///|
test "RpcRequest::from_json: invalid (empty object)" {
  assert_eq(RpcRequest::from_json(Json::object({})), None)
}

///|
test "RpcRequest::from_json: invalid (not an object)" {
  assert_eq(RpcRequest::from_json(Json::string("hello")), None)
}

///|
test "RpcRequest::from_json: invalid (null)" {
  assert_eq(RpcRequest::from_json(Json::null()), None)
}

// =============================================================================
// RpcRequest::to_json
// =============================================================================

///|
test "RpcRequest::to_json: includes jsonrpc 2.0" {
  let req : RpcRequest = { id: Some(5), rpc_method: "test", params: None }
  let json = req.to_json()
  match json {
    {
      "jsonrpc": String("2.0"),
      "id": Number(id, ..),
      "method": String("test"),
      ..
    } => assert_eq(id.to_int(), 5)
    _ => fail("to_json should include jsonrpc:2.0")
  }
}

///|
test "RpcRequest::to_json: notification (no id)" {
  let req : RpcRequest = { id: None, rpc_method: "notify", params: Some({}) }
  let json = req.to_json()
  match json {
    { "id": _, .. } => fail("Notification should not have id in JSON")
    _ => ()
  }
  match json {
    { "method": String("notify"), "params": Object(_), .. } => ()
    _ => fail("Missing method or params")
  }
}

///|
test "RpcRequest::to_json: no params omitted" {
  let req : RpcRequest = { id: Some(1), rpc_method: "test", params: None }
  let json = req.to_json()
  match json {
    { "params": _, .. } => fail("params should not be present when None")
    _ => ()
  }
}

///|
test "RpcRequest::to_json roundtrip" {
  let original : RpcRequest = {
    id: Some(42),
    rpc_method: "tools/call",
    params: Some({ "name": "Read", "arguments": { "file_path": "/tmp/x" } }),
  }
  let json = original.to_json()
  let parsed = RpcRequest::from_json(json)
  match parsed {
    Some(r) => {
      assert_eq(r.id, Some(42))
      assert_eq(r.rpc_method, "tools/call")
    }
    None => fail("Roundtrip failed")
  }
}

// =============================================================================
// RpcResponse::from_json
// =============================================================================

///|
test "RpcResponse::from_json: success with id" {
  let json : Json = { "id": 1, "result": { "data": "test" } }
  match RpcResponse::from_json(json) {
    Some(r) => {
      assert_eq(r.id, Some(1))
      assert_true(not(r.result is None))
      assert_eq(r.error, None)
    }
    None => fail("Failed to parse success response")
  }
}

///|
test "RpcResponse::from_json: error with id" {
  let json : Json = {
    "id": 1,
    "error": { "code": -32600, "message": "Invalid Request" },
  }
  match RpcResponse::from_json(json) {
    Some(r) => {
      assert_eq(r.id, Some(1))
      assert_eq(r.result, None)
      match r.error {
        Some(e) => {
          assert_eq(e.code, -32600)
          assert_eq(e.message, "Invalid Request")
        }
        None => fail("Expected error")
      }
    }
    None => fail("Failed to parse error response")
  }
}

///|
test "RpcResponse::from_json: result without id" {
  let json : Json = { "result": { "ok": true } }
  match RpcResponse::from_json(json) {
    Some(r) => {
      assert_eq(r.id, None)
      assert_true(not(r.result is None))
    }
    None => fail("Failed to parse result without id")
  }
}

///|
test "RpcResponse::from_json: null result" {
  let json : Json = { "id": 1, "result": Null }
  match RpcResponse::from_json(json) {
    Some(r) => {
      assert_eq(r.id, Some(1))
      match r.result {
        Some(Null) => ()
        _ => fail("Expected null result")
      }
    }
    None => fail("Failed to parse null result")
  }
}

///|
test "RpcResponse::from_json: invalid (no result or error)" {
  assert_eq(RpcResponse::from_json({ "id": 1 }), None)
}

///|
test "RpcResponse::from_json: invalid (empty object)" {
  assert_eq(RpcResponse::from_json(Json::object({})), None)
}

// =============================================================================
// RpcStep / RpcStepKind
// =============================================================================

///|
test "RpcStepKind: equality" {
  assert_eq(@jsonrpc.Request, @jsonrpc.Request)
  assert_eq(@jsonrpc.Notification, @jsonrpc.Notification)
  assert_true(@jsonrpc.Request != @jsonrpc.Notification)
}

///|
test "RpcStep: construction" {
  let step : @jsonrpc.RpcStep = {
    message: "{\"jsonrpc\":\"2.0\"}",
    kind: @jsonrpc.Request,
  }
  assert_eq(step.kind, @jsonrpc.Request)
  assert_true(step.message.length() > 0)
}

// =============================================================================
// Unicode / special characters
// =============================================================================

///|
test "build_request: unicode in method" {
  let msg = build_request(1, "テスト/メソッド", None)
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
  match json {
    { "method": String(m), .. } => assert_eq(m, "テスト/メソッド")
    _ => fail("Unicode method not preserved")
  }
}

///|
test "build_request: special chars in params" {
  let params : Json = {
    "path": "/tmp/file with spaces.txt",
    "content": "line1\nline2\ttab",
  }
  let msg = build_request(1, "test", Some(params))
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
  match json {
    { "params": { "path": String(p), .. }, .. } =>
      assert_eq(p, "/tmp/file with spaces.txt")
    _ => fail("Special chars not preserved in params")
  }
}

///|
test "build_error_response: unicode in message" {
  let msg = build_error_response(
    Some(1),
    -32000,
    "エラーが発生しました",
  )
  let json = @json.parse(msg) catch { _ => fail("Failed to parse") }
  match json {
    { "error": { "message": String(m), .. }, .. } =>
      assert_eq(m, "エラーが発生しました")
    _ => fail("Unicode error message not preserved")
  }
}
