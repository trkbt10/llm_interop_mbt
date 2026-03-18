///|
/// Tests for Responses API → Chat Completions pipeline
/// Based on docs/openai-harmony.md specification

///|
test "instructions field becomes system message" {
  let request : Json = {
    "model": "gpt-oss-20b",
    "instructions": "You are a helpful assistant.",
    "input": [
      { "role": "user", "content": "Hello" },
    ],
  }
  let result = responses_request_to_chat_completions(request, stream=false)
  let messages = match result {
    { "messages": Array(msgs), .. } => msgs
    _ => panic()
  }
  // First message should be system with instructions
  assert_eq(
    match messages[0] {
      { "role": String("system"), "content": String(c), .. } => c
      _ => ""
    },
    "You are a helpful assistant.",
  )
  // Second message should be user
  assert_eq(
    match messages[1] {
      { "role": String("user"), "content": String(c), .. } => c
      _ => ""
    },
    "Hello",
  )
}

///|
test "input with content block array (input_text type)" {
  let request : Json = {
    "model": "gpt-oss-20b",
    "input": [
      {
        "role": "user",
        "content": Json::array([
          { "type": "input_text", "text": "What is 2+2?" },
        ]),
      },
    ],
  }
  let result = responses_request_to_chat_completions(request, stream=false)
  let messages = match result {
    { "messages": Array(msgs), .. } => msgs
    _ => panic()
  }
  assert_eq(
    match messages[0] {
      { "role": String("user"), "content": String(c), .. } => c
      _ => ""
    },
    "What is 2+2?",
  )
}

///|
test "input with plain string content" {
  let request : Json = {
    "model": "gpt-oss-20b",
    "input": "What is 2+2?",
  }
  let result = responses_request_to_chat_completions(request, stream=false)
  let messages = match result {
    { "messages": Array(msgs), .. } => msgs
    _ => panic()
  }
  assert_eq(
    match messages[0] {
      { "role": String("user"), "content": String(c), .. } => c
      _ => ""
    },
    "What is 2+2?",
  )
}

///|
test "function tool: Responses API flat → Chat Completions nested" {
  let request : Json = {
    "model": "gpt-oss-20b",
    "input": [{ "role": "user", "content": "run ls" }],
    "tools": Json::array([
      {
        "type": "function",
        "name": "shell",
        "description": "Execute a shell command",
        "parameters": {
          "type": "object",
          "properties": {
            "command": { "type": "string" },
          },
          "required": Json::array([Json::string("command")]),
        },
      },
    ]),
  }
  let result = responses_request_to_chat_completions(request, stream=false)
  let tools = match result {
    { "tools": Array(t), .. } => t
    _ => panic()
  }
  assert_eq(tools.length(), 1)
  // Should be nested: {type:"function", function:{name:"shell",...}}
  let tool = tools[0]
  assert_eq(
    match tool {
      { "type": String(t), .. } => t
      _ => ""
    },
    "function",
  )
  assert_eq(
    match tool {
      { "function": { "name": String(n), .. }, .. } => n
      _ => ""
    },
    "shell",
  )
  assert_eq(
    match tool {
      { "function": { "description": String(d), .. }, .. } => d
      _ => ""
    },
    "Execute a shell command",
  )
}

///|
test "non-function tools are filtered out" {
  let request : Json = {
    "model": "gpt-oss-20b",
    "input": [{ "role": "user", "content": "hi" }],
    "tools": Json::array([
      {
        "type": "function",
        "name": "shell",
        "description": "Execute a shell command",
        "parameters": { "type": "object", "properties": {} },
      },
      { "type": "container_exec" },
      { "type": "code_interpreter" },
    ]),
  }
  let result = responses_request_to_chat_completions(request, stream=false)
  let tools = match result {
    { "tools": Array(t), .. } => t
    _ => panic()
  }
  // Only the function tool should remain
  assert_eq(tools.length(), 1)
  assert_eq(
    match tools[0] {
      { "function": { "name": String(n), .. }, .. } => n
      _ => ""
    },
    "shell",
  )
}

///|
test "web_search_preview tool converts to function" {
  let request : Json = {
    "model": "gpt-oss-20b",
    "input": [{ "role": "user", "content": "search" }],
    "tools": Json::array([
      { "type": "web_search_preview" },
    ]),
  }
  let result = responses_request_to_chat_completions(request, stream=false)
  let tools = match result {
    { "tools": Array(t), .. } => t
    _ => panic()
  }
  assert_eq(tools.length(), 1)
  assert_eq(
    match tools[0] {
      { "function": { "name": String(n), .. }, .. } => n
      _ => ""
    },
    "web_search",
  )
}

///|
test "already nested Chat Completions tool passes through" {
  let request : Json = {
    "model": "gpt-oss-20b",
    "input": [{ "role": "user", "content": "hi" }],
    "tools": Json::array([
      {
        "type": "function",
        "function": {
          "name": "get_weather",
          "description": "Get weather",
          "parameters": { "type": "object", "properties": {} },
        },
      },
    ]),
  }
  let result = responses_request_to_chat_completions(request, stream=false)
  let tools = match result {
    { "tools": Array(t), .. } => t
    _ => panic()
  }
  assert_eq(tools.length(), 1)
  assert_eq(
    match tools[0] {
      { "function": { "name": String(n), .. }, .. } => n
      _ => ""
    },
    "get_weather",
  )
}

///|
test "model field is preserved" {
  let request : Json = {
    "model": "openai/gpt-oss-20b",
    "input": [{ "role": "user", "content": "hi" }],
  }
  let result = responses_request_to_chat_completions(request, stream=false)
  assert_eq(
    match result {
      { "model": String(m), .. } => m
      _ => ""
    },
    "openai/gpt-oss-20b",
  )
}

///|
test "stream parameter is respected" {
  let request : Json = {
    "model": "gpt-oss-20b",
    "input": [{ "role": "user", "content": "hi" }],
  }
  let streaming = responses_request_to_chat_completions(request, stream=true)
  assert_eq(
    match streaming {
      { "stream": True, .. } => true
      _ => false
    },
    true,
  )
  let non_streaming = responses_request_to_chat_completions(
    request, stream=false,
  )
  assert_eq(
    match non_streaming {
      { "stream": False, .. } => true
      _ => false
    },
    true,
  )
}

///|
test "instructions + input_text content blocks + tools combined" {
  // Simulates a Codex-like request
  let request : Json = {
    "model": "openai/gpt-oss-20b",
    "instructions": "You are a coding agent.",
    "input": Json::array([
      {
        "type": "message",
        "role": "user",
        "content": Json::array([
          { "type": "input_text", "text": "List files in current directory" },
        ]),
      },
    ]),
    "tools": Json::array([
      {
        "type": "function",
        "name": "shell",
        "description": "Run shell command",
        "parameters": {
          "type": "object",
          "properties": { "command": { "type": "string" } },
        },
      },
      { "type": "container_exec" },
    ]),
  }
  let result = responses_request_to_chat_completions(request, stream=false)
  let messages = match result {
    { "messages": Array(msgs), .. } => msgs
    _ => panic()
  }
  // System message from instructions
  assert_eq(
    match messages[0] {
      { "role": String("system"), .. } => true
      _ => false
    },
    true,
  )
  // User message with extracted text
  assert_eq(
    match messages[1] {
      { "role": String("user"), "content": String(c), .. } =>
        c.contains("List files")
      _ => false
    },
    true,
  )
  // Only function tool, container_exec filtered
  let tools = match result {
    { "tools": Array(t), .. } => t
    _ => panic()
  }
  assert_eq(tools.length(), 1)
}
