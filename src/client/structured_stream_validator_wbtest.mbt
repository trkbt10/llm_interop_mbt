///|
/// Whitebox coverage for structured streaming validation

///|
test "structured stream validator ignores non-structured formats" {
  let validator = StructuredStreamValidator::new(None)
  validator.feed("response.output_text.delta", {
    "type": "response.output_text.delta",
    "delta": "not json",
  })
  validator.finish()
}

///|
test "structured stream validator accepts incomplete prefix and completed json object" {
  let validator = StructuredStreamValidator::new(
    Some(@types.ResponseFormat::JsonObject),
  )
  validator.feed("response.output_text.delta", {
    "type": "response.output_text.delta",
    "delta": "{\"answer\":",
  })
  validator.feed("response.output_text.done", {
    "type": "response.output_text.done",
    "text": "{\"answer\":{\"url\":\"https://example.com\"}}",
  })
  validator.finish()
}

///|
test "structured stream validator rejects invalid json prefix" {
  let validator = StructuredStreamValidator::new(
    Some(@types.ResponseFormat::JsonObject),
  )
  let mut caught = false
  validator.feed("response.output_text.delta", {
    "type": "response.output_text.delta",
    "delta": "{\"answer\":oops}",
  }) catch {
    ClientError::ParseError(message) => {
      assert_true(message.contains("not valid JSON"))
      caught = true
    }
    other => ignore(other)
  }
  assert_true(caught)
}

///|
test "structured stream validator rejects schema mismatches" {
  let validator = StructuredStreamValidator::new(
    Some(
      @types.ResponseFormat::JsonSchema(
        name=Some("answer"),
        schema={
          "type": "object",
          "required": ["url"],
          "properties": { "url": { "type": "string", "format": "uri" } },
          "additionalProperties": false,
        },
        description=None,
        strict=Some(true),
      ),
    ),
  )
  let mut caught = false
  validator.feed("response.output_text.done", {
    "type": "response.output_text.done",
    "text": "{\"url\":\"not-a-uri\"}",
  }) catch {
    ClientError::ParseError(message) => {
      assert_true(message.contains("response schema"))
      assert_true(message.contains("$.url"))
      caught = true
    }
    other => ignore(other)
  }
  assert_true(caught)
}

///|
test "structured stream validator rejects incomplete final json" {
  let validator = StructuredStreamValidator::new(
    Some(@types.ResponseFormat::JsonObject),
  )
  validator.feed("response.output_text.delta", {
    "type": "response.output_text.delta",
    "delta": "{\"answer\":",
  })
  let mut caught = false
  validator.finish() catch {
    ClientError::ParseError(message) => {
      assert_true(message.contains("complete JSON value"))
      caught = true
    }
    other => ignore(other)
  }
  assert_true(caught)
}

///|
test "structured stream validator covers completed branch and malformed done fallback" {
  let validator = StructuredStreamValidator::new(
    Some(@types.ResponseFormat::JsonObject),
  )
  validator.record_text_delta(" ")
  let mut empty_caught = false
  validator.feed("response.completed", {}) catch {
    ClientError::ParseError(message) => {
      assert_true(message.contains("without JSON content"))
      empty_caught = true
    }
    other => ignore(other)
  }
  assert_true(empty_caught)

  let validator2 = StructuredStreamValidator::new(
    Some(@types.ResponseFormat::JsonObject),
  )
  validator2.record_text_delta("{\"answer\":")
  let mut done_caught = false
  validator2.feed("response.output_text.done", {}) catch {
    ClientError::ParseError(message) => {
      assert_true(message.contains("complete JSON value"))
      done_caught = true
    }
    other => ignore(other)
  }
  assert_true(done_caught)

  let validator3 = StructuredStreamValidator::new(
    Some(@types.ResponseFormat::JsonObject),
  )
  validator3.feed("response.output_text.delta", {})
}

///|
test "structured stream validator helper methods cover non-structured branches" {
  assert_false(
    should_validate_structured_stream(Some(@types.ResponseFormat::Text)),
  )
  assert_true(
    should_validate_structured_stream(Some(@types.ResponseFormat::JsonObject)),
  )
  assert_false(should_validate_structured_stream(None))

  let none_validator = StructuredStreamValidator::new(None)
  none_validator.validate_json_value(Json::string("plain"))

  let json_object_validator = StructuredStreamValidator::new(
    Some(@types.ResponseFormat::JsonObject),
  )
  let mut root_caught = false
  json_object_validator.validate_json_value(Json::array([])) catch {
    ClientError::ParseError(message) => {
      assert_true(message.contains("JSON object"))
      root_caught = true
    }
    other => ignore(other)
  }
  assert_true(root_caught)

  let json_schema_validator = StructuredStreamValidator::new(
    Some(
      @types.ResponseFormat::JsonSchema(
        name=None,
        schema={ "type": "object", "required": ["answer"] },
        description=None,
        strict=None,
      ),
    ),
  )
  json_schema_validator.validate_json_value({ "answer": "ok" })
}

///|
test "schema validation covers composition, const, enum, and type branches" {
  let all_of_error = schema_validation_error(
    { "value": 1 },
    {
      "allOf": [
        { "type": "object", "required": ["value"] },
        { "type": "object", "required": ["missing"] },
      ],
    },
    "$",
  )
  assert_true(all_of_error.unwrap_or("").contains("missing required property"))

  let any_of_error = schema_validation_error(
    Json::number(3.0),
    { "anyOf": [{ "type": "string" }, { "type": "boolean" }] },
    "$",
  )
  assert_true(
    any_of_error.unwrap_or("").contains("does not match any allowed schema"),
  )

  let one_of_error = schema_validation_error(
    Json::number(1.0),
    { "oneOf": [{ "type": "number" }, { "type": "integer" }] },
    "$",
  )
  assert_true(one_of_error.unwrap_or("").contains("exactly one schema"))

  let const_error = schema_validation_error(
    Json::string("b"),
    { "const": "a" },
    "$",
  )
  assert_true(const_error.unwrap_or("").contains("must equal"))

  let enum_error = schema_validation_error(
    Json::string("c"),
    { "enum": ["a", "b"] },
    "$",
  )
  assert_true(enum_error.unwrap_or("").contains("enum"))

  let type_error = schema_validation_error(
    Json::boolean(true),
    { "type": "string" },
    "$",
  )
  assert_true(type_error.unwrap_or("").contains("got boolean"))

  let union_type_error = schema_validation_error(
    Json::number(2.5),
    { "type": ["string", "boolean", 1] },
    "$",
  )
  assert_true(
    union_type_error.unwrap_or("").contains("one of [string, boolean]"),
  )

  assert_eq(
    schema_validation_error(Json::string("ok"), Json::string("ignored"), "$"),
    None,
  )
}

///|
test "schema validation covers object keywords" {
  let missing_required = schema_validation_error(
    {},
    {
      "type": "object",
      "required": ["answer", 1],
      "properties": { "answer": { "type": "string" } },
    },
    "$",
  )
  assert_true(
    missing_required
    .unwrap_or("")
    .contains("missing required property `answer`"),
  )

  let additional_props = schema_validation_error(
    { "answer": "ok", "extra": 1 },
    {
      "type": "object",
      "properties": { "answer": { "type": "string" } },
      "additionalProperties": false,
    },
    "$",
  )
  assert_true(
    additional_props.unwrap_or("").contains("unsupported property `extra`"),
  )

  let extra_schema_error = schema_validation_error(
    { "extra": 1 },
    { "type": "object", "additionalProperties": { "type": "string" } },
    "$",
  )
  assert_true(extra_schema_error.unwrap_or("").contains("$.extra"))

  assert_eq(
    schema_validation_error(
      { "answer": "ok" },
      { "type": "object", "properties": { "answer": { "type": "string" } } },
      "$",
    ),
    None,
  )
}

///|
test "schema validation covers array, string, and number keywords" {
  let min_items = schema_validation_error(
    [],
    { "type": "array", "minItems": 1 },
    "$",
  )
  assert_true(min_items.unwrap_or("").contains("at least 1"))

  let max_items = schema_validation_error(
    [1, 2],
    { "type": "array", "maxItems": 1 },
    "$",
  )
  assert_true(max_items.unwrap_or("").contains("at most 1"))

  let item_error = schema_validation_error(
    [1],
    { "type": "array", "items": { "type": "string" } },
    "$",
  )
  assert_true(item_error.unwrap_or("").contains("$[0]"))

  let min_length = schema_validation_error(
    Json::string("a"),
    { "type": "string", "minLength": 2 },
    "$",
  )
  assert_true(min_length.unwrap_or("").contains("at least 2"))

  let max_length = schema_validation_error(
    Json::string("abcd"),
    { "type": "string", "maxLength": 3 },
    "$",
  )
  assert_true(max_length.unwrap_or("").contains("at most 3"))

  let email_error = schema_validation_error(
    Json::string("bad-email"),
    { "type": "string", "format": "email" },
    "$",
  )
  assert_true(email_error.unwrap_or("").contains("valid email"))

  let date_error = schema_validation_error(
    Json::string("2026-3-1"),
    { "type": "string", "format": "date" },
    "$",
  )
  assert_true(date_error.unwrap_or("").contains("valid date"))

  assert_eq(
    schema_validation_error(
      Json::string("ok"),
      { "type": "string", "format": "custom" },
      "$",
    ),
    None,
  )

  let minimum_error = schema_validation_error(
    Json::number(1.0),
    { "type": "number", "minimum": 2 },
    "$",
  )
  assert_true(minimum_error.unwrap_or("").contains(">= 2"))

  let maximum_error = schema_validation_error(
    Json::number(3.0),
    { "type": "number", "maximum": 2 },
    "$",
  )
  assert_true(maximum_error.unwrap_or("").contains("<= 2"))

  let exclusive_min = schema_validation_error(
    Json::number(2.0),
    { "type": "number", "exclusiveMinimum": 2 },
    "$",
  )
  assert_true(exclusive_min.unwrap_or("").contains("> 2"))

  let exclusive_max = schema_validation_error(
    Json::number(2.0),
    { "type": "number", "exclusiveMaximum": 2 },
    "$",
  )
  assert_true(exclusive_max.unwrap_or("").contains("< 2"))
}

///|
test "schema validation helper predicates cover remaining primitive branches" {
  assert_true(matches_json_schema_type(Json::null(), "null"))
  assert_true(matches_json_schema_type(Json::boolean(false), "boolean"))
  assert_true(matches_json_schema_type(Json::number(1.2), "number"))
  assert_true(matches_json_schema_type(Json::number(1.0), "integer"))
  assert_true(matches_json_schema_type(Json::string("x"), "string"))
  assert_true(matches_json_schema_type(Json::array([]), "array"))
  assert_true(matches_json_schema_type({}, "object"))
  assert_false(matches_json_schema_type(Json::number(1.5), "integer"))
  assert_false(matches_json_schema_type(Json::string("x"), "unknown"))

  assert_true(matches_json_boolean(Json::boolean(true)))
  assert_false(matches_json_boolean(Json::string("true")))
  assert_true(matches_json_integer(Json::number(3.0)))
  assert_false(matches_json_integer(Json::number(3.5)))

  assert_eq(json_value_type_name(Json::null()), "null")
  assert_eq(json_value_type_name(Json::boolean(true)), "boolean")
  assert_eq(json_value_type_name(Json::number(1.5)), "number")
  assert_eq(json_value_type_name(Json::number(2.0)), "integer")
  assert_eq(json_value_type_name(Json::string("x")), "string")
  assert_eq(json_value_type_name(Json::array([])), "array")
  assert_eq(json_value_type_name({}), "object")

  assert_true(looks_like_uri("https://example.com"))
  assert_true(looks_like_uri("urn:test:123"))
  assert_false(looks_like_uri("not a uri"))
  assert_true(looks_like_email("user@example.com"))
  assert_false(looks_like_email("user-at-example.com"))
  assert_true(looks_like_date("2026-03-23"))
  assert_false(looks_like_date("2026-3-23"))
}
