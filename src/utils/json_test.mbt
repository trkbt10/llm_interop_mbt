///|
/// JSON helper tests

///|
test "set_json_field updates objects and leaves non-objects unchanged" {
  let updated = set_json_field({ "existing": "value" }, "added", {
    "nested": true,
  })
  match updated {
    { "existing": String(existing), "added": { "nested": True, .. }, .. } =>
      assert_eq(existing, "value")
    _ => fail("Expected object field to be added")
  }

  match
    set_json_field(Json::string("plain"), "ignored", Json::string("value")) {
    String(value) => assert_eq(value, "plain")
    _ => fail("Expected scalar JSON to be returned unchanged")
  }
}

///|
test "extract_json_field handles parse, type, and shape failures" {
  assert_eq(extract_json_field("{\"name\":\"moon\"}", "name"), Some("moon"))
  assert_eq(extract_json_field("{\"name\":1}", "name"), None)
  assert_eq(extract_json_field("[1,2,3]", "name"), None)
  assert_eq(extract_json_field("not json", "name"), None)
}

///|
test "inject_json_field preserves existing and non-object bodies" {
  let injected = inject_json_field("{\"name\":\"moon\"}", "id", "resp_1")
  let injected_json : Json = @json.parse(injected) catch {
    _ => fail("parse error")
  }
  match injected_json {
    { "name": String(name), "id": String(id), .. } => {
      assert_eq(name, "moon")
      assert_eq(id, "resp_1")
    }
    _ => fail("Expected injected id field")
  }

  let existing = "{\"id\":\"resp_0\"}"
  assert_eq(inject_json_field(existing, "id", "resp_1"), existing)

  let array_body = "[1,2,3]"
  assert_eq(inject_json_field(array_body, "id", "resp_1"), array_body)

  let invalid = "nope"
  assert_eq(inject_json_field(invalid, "id", "resp_1"), invalid)
}
