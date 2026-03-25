///|
/// OpenAI Chat contract builders shared by cross-dialect transforms.

///|
pub fn message_to_json(message : @types.ModelMessage) -> Json {
  match message {
    @types.ModelMessage::System(content) =>
      { "role": "system", "content": content }
    @types.ModelMessage::User(content~, name~, content_parts~) =>
      match content_parts {
        Some(parts) => {
          let content_json = content_parts_to_openai_json(parts)
          match name {
            Some(n) =>
              {
                "role": "user",
                "content": Json::array(content_json),
                "name": n,
              }
            None => { "role": "user", "content": Json::array(content_json) }
          }
        }
        None =>
          match name {
            Some(n) => { "role": "user", "content": content, "name": n }
            None => { "role": "user", "content": content }
          }
      }
    @types.ModelMessage::Assistant(content~, tool_calls~) =>
      match tool_calls {
        Some(calls) => {
          let tool_calls_json : Array[Json] = []
          for call in calls {
            tool_calls_json.push({
              "id": call.id,
              "type": "function",
              "function": {
                "name": call.name,
                "arguments": call.arguments.stringify(),
              },
            })
          }
          {
            "role": "assistant",
            "content": content,
            "tool_calls": Json::array(tool_calls_json),
          }
        }
        None => { "role": "assistant", "content": content }
      }
    @types.ModelMessage::ToolResult(tool_call_id~, content~) =>
      { "role": "tool", "tool_call_id": tool_call_id, "content": content }
  }
}

///|
pub fn chat_request_to_responses_request(body : String) -> Json {
  let json = @json.parse(body) catch {
    _ =>
      abort(
        "OpenAI Chat contract bridge requires valid OpenAI Chat JSON: " + body,
      )
  }
  let request : Map[String, Json] = {}
  match json {
    { "model": String(model), .. } => request["model"] = Json::string(model)
    _ =>
      abort(
        "OpenAI Chat contract bridge requires a model string: " +
        json.stringify(),
      )
  }
  let messages = extract_chat_messages_or_abort(json)
  let system = extract_system_instructions(messages)
  if system.length() > 0 {
    request["instructions"] = Json::string(system)
  }
  let non_system_messages = exclude_system_messages(messages)
  request["input"] = Json::array(
    @openai_responses_contract.messages_to_responses_input(non_system_messages),
  )
  @types.GenerationParams::from_openai(json).apply_to_responses(request)
  match json {
    { "tools": Array(tools), .. } =>
      if tools.length() > 0 {
        request["tools"] = Json::array(chat_tools_to_responses_tools(tools))
      }
    _ => ()
  }
  match json {
    { "tool_choice": tool_choice, .. } =>
      match openai_chat_tool_choice_to_responses(tool_choice) {
        Some(choice) => request["tool_choice"] = choice
        None => ()
      }
    _ => ()
  }
  Json::object(request)
}

///|
fn content_parts_to_openai_json(
  parts : Array[@types.ContentPart],
) -> Array[Json] {
  let result : Array[Json] = []
  for part in parts {
    match part {
      @types.ContentPart::Text(text) =>
        result.push({ "type": "text", "text": text })
      @types.ContentPart::ImageUrl(url~, detail~) => {
        let image_url : Map[String, Json] = { "url": Json::string(url) }
        match detail {
          Some(d) => image_url["detail"] = Json::string(d)
          None => ()
        }
        result.push({
          "type": "image_url",
          "image_url": Json::object(image_url),
        })
      }
      @types.ContentPart::ImageBase64(data~, media_type~) =>
        result.push({
          "type": "image_url",
          "image_url": { "url": "data:\{media_type};base64,\{data}" },
        })
      @types.ContentPart::Audio(data~, format~) =>
        result.push({
          "type": "input_audio",
          "input_audio": { "data": data, "format": format },
        })
      @types.ContentPart::Document(data~, media_type~, title~) => {
        let file : Map[String, Json] = {
          "file_data": Json::string("data:\{media_type};base64,\{data}"),
        }
        match title {
          Some(name) => file["filename"] = Json::string(name)
          None => ()
        }
        result.push({ "type": "file", "file": Json::object(file) })
      }
      @types.ContentPart::FileRef(file_id~, ..) =>
        result.push({ "type": "file", "file": { "file_id": file_id } })
      @types.ContentPart::FileUrl(url~) =>
        abort(
          "OpenAI Chat contract does not support remote file URLs; use Responses API or upload via Files API: \{url}",
        )
      @types.ContentPart::Video(..) =>
        abort(
          "OpenAI Chat contract does not support video content; use Gemini or upload via Files API",
        )
    }
  }
  result
}

///|
pub fn messages_to_json(messages : Array[@types.ModelMessage]) -> Array[Json] {
  let result : Array[Json] = []
  for msg in messages {
    result.push(message_to_json(msg))
  }
  result
}

///|
pub fn model_response_to_chat_response(
  response : @types.ModelResponse,
  id~ : String,
  model~ : String,
) -> String {
  match response.as_failure() {
    Some(failure) => failure.to_openai_error_json().stringify()
    None => {
      let choice = model_response_to_chat_choice(response)
      build_chat_response(id, model, [choice])
    }
  }
}

///|
pub fn tool_to_json(tool : @types.ToolDefinition) -> Json {
  match tool.kind {
    @types.ToolDefinitionKind::Function =>
      {
        "type": "function",
        "function": {
          "name": tool.name,
          "description": tool.description,
          "parameters": tool.parameters,
        },
      }
    @types.ToolDefinitionKind::Builtin(builtin_type~, ..) =>
      match builtin_type {
        "web_search_preview" | "web_search_preview_2025_03_11" =>
          web_search_tool_to_json()
        _ =>
          {
            "type": "function",
            "function": {
              "name": tool.name,
              "description": tool.description,
              "parameters": tool.parameters,
            },
          }
      }
    @types.ToolDefinitionKind::WebSearchPreview(..)
    | @types.ToolDefinitionKind::WebSearchPreview20250311(..) =>
      web_search_tool_to_json()
  }
}

///|
pub fn web_search_tool_to_json() -> Json {
  {
    "type": "function",
    "function": {
      "name": @types.web_search_tool_name(),
      "description": @types.web_search_tool_description(),
      "parameters": @types.web_search_tool_parameters_schema(),
    },
  }
}

///|
pub fn tools_to_json(tools : Array[@types.ToolDefinition]) -> Array[Json] {
  let result : Array[Json] = []
  for tool in tools {
    result.push(tool_to_json(tool))
  }
  result
}

///|
pub fn build_chat_choice(
  index : Int,
  text_content : String,
  tool_calls : Array[Json],
  annotations? : Array[Json] = [],
) -> Json {
  let message : Map[String, Json] = {}
  message["role"] = Json::string("assistant")
  if tool_calls.length() > 0 {
    if text_content.is_empty() {
      message["content"] = Json::null()
    } else {
      message["content"] = Json::string(text_content)
    }
    message["tool_calls"] = Json::array(tool_calls)
  } else {
    message["content"] = Json::string(text_content)
  }
  if annotations.length() > 0 {
    message["annotations"] = Json::array(annotations)
  }
  let choice : Map[String, Json] = {}
  choice["index"] = Json::number(index.to_double())
  choice["message"] = Json::object(message)
  choice["finish_reason"] = Json::string(
    if tool_calls.length() > 0 {
      "tool_calls"
    } else {
      "stop"
    },
  )
  Json::object(choice)
}

///|
pub fn build_chat_response(
  id : String,
  model : String,
  choices : Array[Json],
) -> String {
  let result : Map[String, Json] = {}
  result["id"] = Json::string(id)
  result["object"] = Json::string("chat.completion")
  result["model"] = Json::string(model)
  result["choices"] = Json::array(choices)
  Json::object(result).stringify()
}

///|
pub fn build_tool_call_json(
  id : String,
  name : String,
  arguments : Json,
) -> Json {
  let func : Map[String, Json] = {}
  func["name"] = Json::string(name)
  func["arguments"] = Json::string(arguments.stringify())
  let tc : Map[String, Json] = {}
  tc["id"] = Json::string(id)
  tc["type"] = Json::string("function")
  tc["function"] = Json::object(func)
  Json::object(tc)
}

///|
fn extract_chat_messages_or_abort(json : Json) -> Array[@types.ModelMessage] {
  match json {
    { "messages": Array(messages), .. } =>
      messages.map(chat_message_to_model_message)
    _ =>
      abort(
        "OpenAI Chat contract bridge requires a messages array: " +
        json.stringify(),
      )
  }
}

///|
fn chat_message_to_model_message(message : Json) -> @types.ModelMessage {
  match message {
    { "role": String("system"), "content": String(content), .. } =>
      @types.ModelMessage::System(content)
    { "role": String("user"), "content": content, .. } => {
      let content_parts = chat_content_to_content_parts(content)
      let text_content = chat_content_to_text(content)
      let name = match message {
        { "name": String(value), .. } => Some(value)
        _ => None
      }
      @types.ModelMessage::User(content=text_content, name~, content_parts~)
    }
    { "role": String("assistant"), "tool_calls": Array(tool_calls), .. } => {
      let content = match message {
        { "content": String(value), .. } => value
        { "content": Null, .. } => ""
        _ => ""
      }
      @types.ModelMessage::Assistant(
        content~,
        tool_calls=Some(tool_calls.map(chat_tool_call_to_request)),
      )
    }
    { "role": String("assistant"), "content": String(content), .. } =>
      @types.ModelMessage::Assistant(content~, tool_calls=None)
    {
      "role": String("tool"),
      "tool_call_id": String(tool_call_id),
      "content": String(content),
      ..
    } => @types.ModelMessage::ToolResult(tool_call_id~, content~)
    _ =>
      abort(
        "OpenAI Chat contract bridge cannot parse message shape: " +
        message.stringify(),
      )
  }
}

///|
fn chat_tool_call_to_request(call : Json) -> @types.ToolCallRequest {
  match call {
    {
      "id": String(id),
      "function": { "name": String(name), "arguments": String(args_str), .. },
      ..
    } =>
      @types.ToolCallRequest::new(
        id~,
        name~,
        arguments=parse_chat_tool_arguments_or_abort(args_str, call),
      )
    _ =>
      abort(
        "OpenAI Chat contract bridge requires complete tool_calls: " +
        call.stringify(),
      )
  }
}

///|
fn parse_chat_tool_arguments_or_abort(args_str : String, call : Json) -> Json {
  @json.parse(args_str) catch {
    _ =>
      abort(
        "OpenAI Chat contract bridge requires valid JSON tool arguments: " +
        call.stringify(),
      )
  }
}

///|
fn chat_content_to_text(content : Json) -> String {
  match content {
    String(text) => text
    Array(parts) => {
      let buf = StringBuilder::new()
      for part in parts {
        match part {
          { "type": String("text"), "text": String(text), .. } =>
            buf.write_string(text)
          _ => ()
        }
      }
      buf.to_string()
    }
    Null => ""
    _ =>
      abort(
        "OpenAI Chat contract bridge requires string or content-part arrays: " +
        content.stringify(),
      )
  }
}

///|
fn chat_content_to_content_parts(content : Json) -> Array[@types.ContentPart]? {
  match content {
    String(_) | Null => None
    Array(parts) => Some(parts.map(chat_content_part_to_content_part))
    _ =>
      abort(
        "OpenAI Chat contract bridge requires string or content-part arrays: " +
        content.stringify(),
      )
  }
}

///|
fn chat_content_part_to_content_part(part : Json) -> @types.ContentPart {
  match part {
    { "type": String("text"), "text": String(text), .. } =>
      @types.ContentPart::Text(text)
    { "type": String("image_url"), "image_url": { "url": String(url), .. }, .. } => {
      let detail = match part {
        { "image_url": { "detail": String(value), .. }, .. } => Some(value)
        _ => None
      }
      match @utils.parse_data_url(url) {
        Some((media_type, data)) =>
          @types.ContentPart::ImageBase64(data~, media_type~)
        None => @types.ContentPart::ImageUrl(url~, detail~)
      }
    }
    {
      "type": String("input_audio"),
      "input_audio": { "data": String(data), "format": String(format), .. },
      ..
    } => @types.ContentPart::Audio(data~, format~)
    { "type": String("file"), "file": file, .. } =>
      chat_file_part_to_content_part(file, part)
    _ =>
      abort(
        "OpenAI Chat contract bridge cannot parse content part: " +
        part.stringify(),
      )
  }
}

///|
fn chat_file_part_to_content_part(
  file : Json,
  original : Json,
) -> @types.ContentPart {
  match file {
    { "file_id": String(file_id), .. } =>
      @types.ContentPart::FileRef(file_id~, media_type=None)
    { "file_data": String(data_url), .. } =>
      match @utils.parse_data_url(data_url) {
        Some((media_type, data)) =>
          @types.ContentPart::Document(
            data~,
            media_type~,
            title=match file {
              { "filename": String(name), .. } => Some(name)
              _ => None
            },
          )
        None =>
          abort(
            "OpenAI Chat contract bridge requires file_data as data URL: " +
            original.stringify(),
          )
      }
    _ =>
      abort(
        "OpenAI Chat contract bridge cannot parse file content part: " +
        original.stringify(),
      )
  }
}

///|
fn extract_system_instructions(messages : Array[@types.ModelMessage]) -> String {
  let result = StringBuilder::new()
  for message in messages {
    match message {
      @types.ModelMessage::System(content) => {
        if result.to_string().length() > 0 {
          result.write_string("\n\n")
        }
        result.write_string(content)
      }
      _ => ()
    }
  }
  result.to_string()
}

///|
fn exclude_system_messages(
  messages : Array[@types.ModelMessage],
) -> Array[@types.ModelMessage] {
  let result : Array[@types.ModelMessage] = []
  for message in messages {
    match message {
      @types.ModelMessage::System(_) => ()
      _ => result.push(message)
    }
  }
  result
}

///|
fn chat_tools_to_responses_tools(tools : Array[Json]) -> Array[Json] {
  let result : Array[Json] = []
  for tool in tools {
    match tool {
      {
        "type": String("function"),
        "function": { "name": String(name), .. } as function,
        ..
      } => {
        let flat : Map[String, Json] = {
          "type": Json::string("function"),
          "name": Json::string(name),
        }
        match function {
          { "description": String(description), .. } =>
            flat["description"] = Json::string(description)
          _ => ()
        }
        match function {
          { "parameters": parameters, .. } => flat["parameters"] = parameters
          _ => ()
        }
        match function {
          { "strict": strict, .. } => flat["strict"] = strict
          _ => ()
        }
        result.push(Json::object(flat))
      }
      _ =>
        abort(
          "OpenAI Chat contract bridge cannot translate tool definition: " +
          tool.stringify(),
        )
    }
  }
  result
}

///|
fn openai_chat_tool_choice_to_responses(tool_choice : Json) -> Json? {
  match tool_choice {
    String("auto") | String("none") | String("required") => Some(tool_choice)
    { "type": String("function"), "function": { "name": String(name), .. }, .. } =>
      Some({ "type": "function", "name": name })
    _ => None
  }
}

///|
fn model_response_to_chat_choice(response : @types.ModelResponse) -> Json {
  match response {
    @types.ModelResponse::Text(content) => build_chat_choice(0, content, [])
    @types.ModelResponse::RichText(rich) =>
      build_chat_choice(
        0,
        rich_text_to_openai_chat_content(rich),
        [],
        annotations=chat_annotations_from_response_annotations(rich.annotations),
      )
    @types.ModelResponse::ToolCalls(tool_calls) =>
      build_chat_choice(0, "", tool_calls.map(tool_call_to_chat_tool_call))
    @types.ModelResponse::ToolCallsWithContent(tool_calls~, rich~) =>
      build_chat_choice(
        0,
        rich_text_to_openai_chat_content(rich),
        tool_calls.map(tool_call_to_chat_tool_call),
        annotations=chat_annotations_from_response_annotations(rich.annotations),
      )
    _ =>
      abort(
        "OpenAI Chat contract cannot represent this response variant without loss; use Responses pipeline instead",
      )
  }
}

///|
fn tool_call_to_chat_tool_call(call : @types.ToolCallRequest) -> Json {
  match call.kind {
    @types.ToolCallKind::Function =>
      build_tool_call_json(
        @interop_util.convert_tool_call_id_to(
          call.id,
          @interop_util.ToolCallIdProvider::OpenAIChatCompletions,
        ),
        call.name,
        call.arguments,
      )
    _ =>
      abort(
        "OpenAI Chat contract cannot represent non-function tool calls; use Responses pipeline instead: " +
        call.id,
      )
  }
}

///|
fn rich_text_to_openai_chat_content(rich : @types.RichTextResponse) -> String {
  match rich.content_parts {
    Some(parts) => {
      let texts : Array[String] = []
      for part in parts {
        match part {
          @types.ResponseContentPart::OutputText(text) => texts.push(text)
          _ =>
            abort(
              "OpenAI Chat contract cannot represent non-text response content without loss; use Responses pipeline instead: " +
              part.to_string(),
            )
        }
      }
      texts
      .iter()
      .fold(init="", fn(acc, text) { if acc == "" { text } else { acc + text } })
    }
    None => rich.content
  }
}

///|
pub fn chat_annotations_from_response_annotations(
  annotations : Array[@types.ResponseAnnotation],
) -> Array[Json] {
  let result : Array[Json] = []
  for annotation in annotations {
    match response_annotation_to_chat_annotation(annotation) {
      Some(item) => result.push(item)
      None =>
        abort(
          "OpenAI Chat contract cannot represent response annotation without loss; use Responses pipeline instead: \{annotation.to_interop_json().stringify()}",
        )
    }
  }
  result
}

///|
fn response_annotation_to_chat_annotation(
  annotation : @types.ResponseAnnotation,
) -> Json? {
  match annotation {
    @types.ResponseAnnotation::UrlCitation(
      title~,
      url~,
      start_index~,
      end_index~
    ) =>
      Some({
        "type": "url_citation",
        "url_citation": {
          "title": match title {
            Some(value) => value
            None => ""
          },
          "url": url,
          "start_index": start_index,
          "end_index": end_index,
        },
      })
    @types.ResponseAnnotation::WebSearchResultCitation(
      title~,
      url~,
      start_index~,
      end_index~,
      ..
    ) =>
      Some({
        "type": "url_citation",
        "url_citation": {
          "title": title,
          "url": url,
          "start_index": start_index,
          "end_index": end_index,
        },
      })
    @types.ResponseAnnotation::GeminiGroundingCitation(
      chunk~,
      start_index~,
      end_index~,
      ..
    ) =>
      match
        gemini_grounding_chunk_to_chat_url_citation(
          chunk, start_index, end_index,
        ) {
        Some(item) => Some(item)
        None => None
      }
    _ => None
  }
}

///|
fn gemini_grounding_chunk_to_chat_url_citation(
  chunk : Json,
  start_index : Int,
  end_index : Int,
) -> Json? {
  match chunk {
    { "web": { "uri": String(url), .. }, .. } =>
      Some({
        "type": "url_citation",
        "url_citation": {
          "title": match chunk {
            { "web": { "title": String(value), .. }, .. } => value
            _ => ""
          },
          "url": url,
          "start_index": start_index,
          "end_index": end_index,
        },
      })
    { "retrievedContext": { "uri": String(url), .. }, .. } =>
      Some({
        "type": "url_citation",
        "url_citation": {
          "title": match chunk {
            { "retrievedContext": { "title": String(value), .. }, .. } => value
            _ => ""
          },
          "url": url,
          "start_index": start_index,
          "end_index": end_index,
        },
      })
    { "maps": { "uri": String(url), .. }, .. } =>
      Some({
        "type": "url_citation",
        "url_citation": {
          "title": match chunk {
            { "maps": { "title": String(value), .. }, .. } => value
            _ => ""
          },
          "url": url,
          "start_index": start_index,
          "end_index": end_index,
        },
      })
    { "image": { "sourceUri": String(url), .. }, .. } =>
      Some({
        "type": "url_citation",
        "url_citation": {
          "title": match chunk {
            { "image": { "title": String(value), .. }, .. } => value
            _ => ""
          },
          "url": url,
          "start_index": start_index,
          "end_index": end_index,
        },
      })
    _ => None
  }
}
