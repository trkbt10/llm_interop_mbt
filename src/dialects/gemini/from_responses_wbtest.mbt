///|
/// Whitebox coverage for Responses API -> Gemini conversion

///|
test "responses_request_to_gemini preserves valid tool translations" {
  let result = responses_request_to_gemini({
    "model": "gemini-2.0-flash",
    "input": [{ "role": "user", "content": "Hi" }],
    "tools": [
      {
        "type": "function",
        "name": "lookup",
        "description": "Search docs",
        "parameters": { "type": "object", "properties": {} },
      },
      { "type": "googleSearch", "mode": "auto" },
    ],
  })
  match result {
    { "tools": Array(tools), .. } =>
      match tools[0] {
        {
          "functionDeclarations": Array(decls),
          "googleSearch": { "mode": String(mode), .. },
          ..
        } =>
          match decls[0] {
            { "name": String(name), "description": String(description), .. } => {
              assert_eq(name, "lookup")
              assert_eq(description, "Search docs")
              assert_eq(mode, "auto")
            }
            _ => fail("Expected function declaration")
          }
        _ => fail("Expected Gemini tools")
      }
    _ => fail("Expected Gemini request body")
  }
}

///|
test "responses_request_to_gemini normalizes omitted function tool metadata" {
  let result = responses_request_to_gemini({
    "model": "gemini-2.0-flash",
    "tools": [{ "type": "function", "name": "lookup" }],
  })
  match result {
    { "tools": Array(tools), .. } =>
      match tools[0] {
        { "functionDeclarations": Array(decls), .. } =>
          match decls[0] {
            {
              "name": String(name),
              "description": String(description),
              "parameters": Object(parameters),
              ..
            } => {
              assert_eq(name, "lookup")
              assert_eq(description, "")
              assert_eq(parameters.length(), 0)
            }
            _ => fail("Expected normalized function declaration")
          }
        _ => fail("Expected Gemini tools")
      }
    _ => fail("Expected Gemini request body")
  }
}

///|
test "panic responses_request_to_gemini rejects unsupported tool items" {
  responses_request_to_gemini({
    "model": "gemini-2.0-flash",
    "tools": [Json::number(1.0)],
  })
  |> ignore
}
