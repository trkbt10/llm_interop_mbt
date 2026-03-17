///|
/// Schema normalizer tests
/// Ported from llm-interop TypeScript: adapters/claude-to-openai/schema-normalizer.spec.ts

// =============================================================================
// Required properties normalization
// =============================================================================

///|
test "normalize: adds all properties to required array" {
  let schema : Json = {
    "type": "object",
    "properties": {
      "name": { "type": "string" },
      "age": { "type": "number" },
      "active": { "type": "boolean" },
    },
  }
  let result = normalize_json_schema_for_openai(schema)
  match result {
    { "required": Array(required), .. } => {
      assert_eq(required.length(), 3)
      // Check all properties are present
      let mut found_name = false
      let mut found_age = false
      let mut found_active = false
      for r in required {
        match r {
          String("name") => found_name = true
          String("age") => found_age = true
          String("active") => found_active = true
          _ => ()
        }
      }
      assert_true(found_name)
      assert_true(found_age)
      assert_true(found_active)
    }
    _ => fail("Expected required array")
  }
}

///|
test "normalize: handles nested object properties" {
  let schema : Json = {
    "type": "object",
    "properties": {
      "user": {
        "type": "object",
        "properties": {
          "name": { "type": "string" },
          "email": { "type": "string" },
        },
      },
    },
  }
  let result = normalize_json_schema_for_openai(schema)
  match result {
    {
      "properties": {
        "user": {
          "required": Array(user_required),
          "additionalProperties": False,
          ..
        },
        ..
      },
      "required": Array(top_required),
      "additionalProperties": False,
      ..
    } => {
      assert_eq(top_required.length(), 1)
      assert_eq(user_required.length(), 2)
    }
    _ => fail("Expected nested required arrays")
  }
}

///|
test "normalize: handles array items with object schemas" {
  let schema : Json = {
    "type": "object",
    "properties": {
      "items": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "id": { "type": "string" },
            "value": { "type": "number" },
          },
        },
      },
    },
  }
  let result = normalize_json_schema_for_openai(schema)
  match result {
    {
      "properties": {
        "items": {
          "items": {
            "required": Array(item_required),
            "additionalProperties": False,
            ..
          },
          ..
        },
        ..
      },
      ..
    } => assert_eq(item_required.length(), 2)
    _ => fail("Expected array items normalization")
  }
}

///|
test "normalize: handles empty properties" {
  let schema : Json = { "type": "object", "properties": {} }
  let result = normalize_json_schema_for_openai(schema)
  match result {
    { "additionalProperties": False, .. } => ()
    _ => fail("Expected additionalProperties: false")
  }
}

// =============================================================================
// Format removal
// =============================================================================

///|
test "normalize: removes uri format" {
  let schema : Json = {
    "type": "object",
    "properties": {
      "website": { "type": "string", "format": "uri" },
      "email": { "type": "string", "format": "email" },
    },
  }
  let result = normalize_json_schema_for_openai(schema)
  match result {
    {
      "properties": { "website": website_schema, "email": email_schema, .. },
      ..
    } => {
      // uri format should be removed
      match website_schema {
        { "format": _, .. } => fail("uri format should be removed")
        _ => ()
      }
      // email format should be preserved
      match email_schema {
        { "format": String("email"), .. } => ()
        _ => fail("email format should be preserved")
      }
    }
    _ => fail("Expected properties")
  }
}

///|
test "normalize: removes uri format from nested schemas" {
  let schema : Json = {
    "type": "object",
    "properties": {
      "links": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": { "url": { "type": "string", "format": "uri" } },
        },
      },
    },
  }
  let result = normalize_json_schema_for_openai(schema)
  match result {
    {
      "properties": {
        "links": {
          "items": { "properties": { "url": url_schema, .. }, .. },
          ..
        },
        ..
      },
      ..
    } =>
      match url_schema {
        { "format": _, .. } => fail("Nested uri format should be removed")
        _ => ()
      }
    _ => fail("Expected nested structure")
  }
}

// =============================================================================
// additionalProperties normalization
// =============================================================================

///|
test "normalize: sets additionalProperties to false" {
  let schema : Json = {
    "type": "object",
    "properties": { "name": { "type": "string" } },
  }
  let result = normalize_json_schema_for_openai(schema)
  match result {
    { "additionalProperties": False, .. } => ()
    _ => fail("Expected additionalProperties: false")
  }
}

///|
test "normalize: overrides existing additionalProperties true" {
  let schema : Json = {
    "type": "object",
    "properties": { "name": { "type": "string" } },
    "additionalProperties": true,
  }
  let result = normalize_json_schema_for_openai(schema)
  match result {
    { "additionalProperties": False, .. } => ()
    _ => fail("Expected additionalProperties to be overridden to false")
  }
}

///|
test "normalize: recursively sets additionalProperties for nested objects" {
  let schema : Json = {
    "type": "object",
    "properties": {
      "user": {
        "type": "object",
        "properties": { "name": { "type": "string" } },
        "additionalProperties": true,
      },
    },
  }
  let result = normalize_json_schema_for_openai(schema)
  match result {
    {
      "properties": { "user": { "additionalProperties": False, .. }, .. },
      "additionalProperties": False,
      ..
    } => ()
    _ => fail("Expected all additionalProperties to be false")
  }
}

// =============================================================================
// Complex scenarios
// =============================================================================

///|
test "normalize: handles function schema with all normalizations" {
  let schema : Json = {
    "type": "object",
    "properties": {
      "query": { "type": "string", "description": "Search query" },
      "filters": {
        "type": "object",
        "properties": {
          "source_url": { "type": "string", "format": "uri" },
          "date": { "type": "string", "format": "date" },
        },
        "additionalProperties": true,
      },
    },
    "required": Json::array([Json::string("query")]),
  }
  let result = normalize_json_schema_for_openai(schema)
  // Check top-level
  match result {
    { "required": Array(req), "additionalProperties": False, .. } =>
      assert_eq(req.length(), 2) // query + filters
    _ => fail("Top-level normalization failed")
  }
  // Check nested filters
  match result {
    {
      "properties": {
        "filters": {
          "required": Array(filter_req),
          "additionalProperties": False,
          "properties": { "source_url": source_schema, "date": date_schema, .. },
          ..
        },
        ..
      },
      ..
    } => {
      assert_eq(filter_req.length(), 2)
      // uri format removed
      match source_schema {
        { "format": _, .. } => fail("uri format should be removed")
        _ => ()
      }
      // date format preserved
      match date_schema {
        { "format": String("date"), .. } => ()
        _ => fail("date format should be preserved")
      }
    }
    _ => fail("Nested normalization failed")
  }
}

// =============================================================================
// Edge cases
// =============================================================================

///|
test "normalize: handles empty schema" {
  let schema : Json = {}
  let result = normalize_json_schema_for_openai(schema)
  match result {
    Object(map) => assert_eq(map.length(), 0)
    _ => fail("Expected empty object")
  }
}

///|
test "normalize: handles non-object type schemas" {
  let schema : Json = { "type": "string" }
  let result = normalize_json_schema_for_openai(schema)
  match result {
    { "additionalProperties": _, .. } =>
      fail("Non-object schemas shouldn't have additionalProperties")
    _ => ()
  }
}

///|
test "normalize: preserves description and enum" {
  let schema : Json = {
    "type": "object",
    "properties": {
      "status": {
        "type": "string",
        "enum": Json::array([Json::string("active"), Json::string("inactive")]),
        "description": "User status",
      },
    },
  }
  let result = normalize_json_schema_for_openai(schema)
  match result {
    {
      "properties": {
        "status": { "enum": Array(enums), "description": String(desc), .. },
        ..
      },
      ..
    } => {
      assert_eq(enums.length(), 2)
      assert_eq(desc, "User status")
    }
    _ => fail("Should preserve enum and description")
  }
}

// =============================================================================
// Needs normalization check
// =============================================================================

///|
test "needs_normalization: returns true for missing additionalProperties" {
  let schema : Json = {
    "type": "object",
    "properties": { "name": { "type": "string" } },
  }
  assert_true(schema_needs_normalization(schema))
}

///|
test "needs_normalization: returns true for uri format" {
  let schema : Json = { "type": "string", "format": "uri" }
  assert_true(schema_needs_normalization(schema))
}

///|
test "needs_normalization: returns false for already normalized schema" {
  let schema : Json = {
    "type": "object",
    "properties": { "name": { "type": "string" } },
    "required": Json::array([Json::string("name")]),
    "additionalProperties": false,
  }
  assert_false(schema_needs_normalization(schema))
}
