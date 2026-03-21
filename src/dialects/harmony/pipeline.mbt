///|
/// Full pipeline: Responses API Request -> Chat Completions -> Responses API Response

///|
/// Convert Responses API request to Chat Completions request body
pub fn responses_request_to_chat_completions(
  request : Json,
  stream? : Bool = true,
) -> Json {
  let model = match request {
    { "model": String(m), .. } => m
    _ => ""
  }
  let messages : Array[@types.ModelMessage] = []
  // Extract instructions as system message
  match request {
    { "instructions": String(instructions), .. } =>
      messages.push(@types.ModelMessage::System(instructions))
    _ => ()
  }
  // Convert input items to messages
  let input_messages = match request {
    { "input": Array(items), .. } => responses_input_to_messages(items)
    { "input": String(text), .. } =>
      [@types.ModelMessage::User(content=text, name=None)]
    _ => []
  }
  for m in input_messages {
    messages.push(m)
  }
  let msgs_json = @openai.messages_to_json(messages)
  // Build Chat Completions body
  let body : Map[String, Json] = {
    "model": Json::string(model),
    "messages": Json::array(msgs_json),
    "stream": Json::boolean(stream),
  }
  // Pass through optional parameters
  match request {
    { "temperature": Number(t, ..), .. } =>
      body["temperature"] = Json::number(t)
    _ => ()
  }
  match request {
    { "top_p": Number(p, ..), .. } => body["top_p"] = Json::number(p)
    _ => ()
  }
  // Responses API: max_output_tokens → Chat Completions: max_tokens
  match request {
    { "max_output_tokens": Number(n, ..), .. } =>
      body["max_tokens"] = Json::number(n)
    _ => ()
  }
  // Convert tools
  match request {
    { "tools": Array(tools), .. } =>
      if tools.length() > 0 {
        body["tools"] = Json::array(convert_responses_tools_to_chat(tools))
        body["tool_choice"] = Json::string("auto")
      }
    _ => ()
  }
  Json::object(body)
}

///|
/// Convert a complete (non-streaming) Chat Completions response into synthetic
/// SSE events that HarmonyToResponsesTranslator can process.
///
/// This enables streaming Responses API output even when the backend only
/// supports synchronous Chat Completions. The translator sees the same event
/// shapes it would see from a real SSE stream.
pub fn chat_completion_to_synthetic_events(
  response_json : Json,
) -> Array[@sse.SseEvent] {
  let events : Array[@sse.SseEvent] = []
  match response_json {
    { "choices": Array(choices), .. } =>
      if choices.length() > 0 {
        let choice = choices[0]
        // 1) Init event: role assignment with empty content
        events.push({
          event: "",
          data: {
            "choices": Json::array([
              {
                "index": 0,
                "delta": { "role": "assistant", "content": "" },
                "finish_reason": Json::null(),
              },
            ]),
          },
        })
        let message = match choice {
          { "message": msg, .. } => msg
          _ => Json::null()
        }
        let finish_reason = match choice {
          { "finish_reason": fr, .. } => fr
          _ => Json::string("stop")
        }
        // 2) Content delta (if present)
        match message {
          { "content": String(content), .. } =>
            if content.length() > 0 {
              events.push({
                event: "",
                data: {
                  "choices": Json::array([
                    {
                      "index": 0,
                      "delta": { "content": content },
                      "finish_reason": Json::null(),
                    },
                  ]),
                },
              })
            }
          _ => ()
        }
        // 3) Tool call deltas (if present)
        match message {
          { "tool_calls": Array(tool_calls), .. } =>
            if tool_calls.length() > 0 {
              let tc_deltas : Array[Json] = []
              for i, tc in tool_calls {
                let tc_obj : Map[String, Json] = {}
                tc_obj["index"] = Json::number(i.to_double())
                match tc {
                  { "id": id, .. } => tc_obj["id"] = id
                  _ => ()
                }
                tc_obj["type"] = Json::string("function")
                match tc {
                  { "function": func, .. } => tc_obj["function"] = func
                  _ => ()
                }
                tc_deltas.push(Json::object(tc_obj))
              }
              events.push({
                event: "",
                data: {
                  "choices": Json::array([
                    {
                      "index": 0,
                      "delta": { "tool_calls": Json::array(tc_deltas) },
                      "finish_reason": Json::null(),
                    },
                  ]),
                },
              })
            }
          _ => ()
        }
        // 4) Finish event
        events.push({
          event: "",
          data: {
            "choices": Json::array([
              {
                "index": 0,
                "delta": Json::object({}),
                "finish_reason": finish_reason,
              },
            ]),
          },
        })
      }
    _ => ()
  }
  events
}

///|
fn convert_responses_tools_to_chat(tools : Array[Json]) -> Array[Json] {
  let result : Array[Json] = []
  for tool in tools {
    match tool {
      { "type": String("web_search_preview"), .. }
      | { "type": String("web_search_preview_2025_03_11"), .. } =>
        result.push(@openai.web_search_tool_to_json())
      // Responses API function tool: flat {type,name,description,parameters}
      // → Chat Completions: nested {type:"function",function:{name,description,parameters}}
      { "type": String("function"), "name": String(name), .. } => {
        let fn_obj : Map[String, Json] = {}
        fn_obj["name"] = Json::string(name)
        match tool {
          { "description": String(desc), .. } =>
            fn_obj["description"] = Json::string(desc)
          _ => ()
        }
        match tool {
          { "parameters": params, .. } => fn_obj["parameters"] = params
          _ => ()
        }
        match tool {
          { "strict": strict, .. } => fn_obj["strict"] = strict
          _ => ()
        }
        result.push({ "type": "function", "function": Json::object(fn_obj) })
      }
      // Already in Chat Completions format (has nested "function" key)
      { "type": String("function"), "function": _, .. } => result.push(tool)
      // Skip non-function tools (container_exec, code_interpreter, etc.)
      // that backends don't understand
      _ => ()
    }
  }
  result
}
