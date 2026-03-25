///|
/// Whitebox coverage for JSON schema normalizer recursion branches

///|
test "normalizer covers array roots and scalar passthrough" {
  let normalized = @types.normalize_json_schema_for_openai(
    Json::array([
      {
        "type": "object",
        "properties": { "url": { "type": "string", "format": "uri" } },
      },
    ]),
  )
  match normalized {
    Array(items) =>
      match items[0] {
        {
          "type": "object",
          "additionalProperties": False,
          "required": Array(required),
          "properties": { "url": { "type": "string", .. }, .. },
          ..
        } => assert_eq(required.length(), 1)
        _ => fail("Expected normalized object schema")
      }
    _ => fail("Expected normalized array schema")
  }

  assert_eq(
    @types.normalize_json_schema_for_openai(Json::string("plain")),
    Json::string("plain"),
  )
}

///|
test "schema_needs_normalization covers required mismatches, nested props, items, and scalars" {
  assert_true(
    @types.schema_needs_normalization({
      "properties": { "a": { "type": "string" } },
    }),
  )
  assert_true(
    @types.schema_needs_normalization({
      "type": "object",
      "additionalProperties": false,
      "properties": { "a": { "type": "string" } },
      "required": Json::array([]),
    }),
  )
  assert_true(
    @types.schema_needs_normalization({
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "nested": {
          "type": "object",
          "properties": { "a": { "type": "string" } },
        },
      },
      "required": Json::array([Json::string("nested")]),
    }),
  )
  assert_true(
    @types.schema_needs_normalization({
      "type": "array",
      "items": { "type": "object", "properties": { "a": { "type": "string" } } },
    }),
  )
  assert_false(@types.schema_needs_normalization(Json::string("plain")))
}
