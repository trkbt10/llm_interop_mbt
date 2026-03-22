///|
/// Responses API input to Chat Completions messages conversion

///|
/// Convert Responses API input items to Chat Completions messages format
/// input: [{ role: "user", content: "..." }, { type: "function_call", ... }, ...]
/// output: Array[@types.ModelMessage]
pub fn responses_input_to_messages(
  input : Array[Json],
) -> Array[@types.ModelMessage] {
  let messages : Array[@types.ModelMessage] = []
  let mut pending_tool_calls : Array[@types.ToolCallRequest] = []
  for item in input {
    match item {
      // System message
      { "role": String("system"), "content": content, .. } =>
        messages.push(
          @types.ModelMessage::System(extract_text_content(content)),
        )
      // User message
      { "role": String("user"), "content": content, .. } => {
        // Flush any pending tool calls as assistant message
        if pending_tool_calls.length() > 0 {
          messages.push(
            @types.ModelMessage::Assistant(
              content="",
              tool_calls=Some(pending_tool_calls),
            ),
          )
          pending_tool_calls = []
        }
        let content_parts = extract_content_parts(content)
        let content = extract_text_content(content)
        messages.push(
          @types.ModelMessage::User(content~, name=None, content_parts~),
        )
      }
      // Assistant message (text only)
      { "role": String("assistant"), "content": content, .. } => {
        // Flush any pending tool calls first
        if pending_tool_calls.length() > 0 {
          messages.push(
            @types.ModelMessage::Assistant(
              content="",
              tool_calls=Some(pending_tool_calls),
            ),
          )
          pending_tool_calls = []
        }
        let content = extract_text_content(content)
        messages.push(@types.ModelMessage::Assistant(content~, tool_calls=None))
      }
      // Function call (Responses API format)
      {
        "type": String("function_call"),
        "name": String(name),
        "arguments": String(args_str),
        ..
      } => {
        let id = match item {
          { "call_id": String(cid), .. } => cid
          { "id": String(fid), .. } => fid
          _ => ""
        }
        let arguments : Json = @json.parse(args_str) catch { _ => {} }
        pending_tool_calls.push(
          @types.ToolCallRequest::new(id~, name~, arguments~),
        )
      }
      // Built-in web search call (Responses API format)
      { "type": String("web_search_call"), "id": String(id), .. } => {
        let query = match item {
          { "action": { "query": String(q), .. }, .. } => Some(q)
          _ => None
        }
        let queries = match item {
          { "action": { "queries": Array(values), .. }, .. } =>
            Some(json_array_to_strings(values))
          _ => None
        }
        pending_tool_calls.push(
          @types.ToolCallRequest::web_search(id~, query~, queries~),
        )
      }
      // Function call output (Responses API format)
      {
        "type": String("function_call_output"),
        "call_id": String(call_id),
        "output": String(output),
        ..
      } => {
        // Flush pending tool calls as assistant message first
        if pending_tool_calls.length() > 0 {
          messages.push(
            @types.ModelMessage::Assistant(
              content="",
              tool_calls=Some(pending_tool_calls),
            ),
          )
          pending_tool_calls = []
        }
        messages.push(
          @types.ModelMessage::ToolResult(tool_call_id=call_id, content=output),
        )
      }
      _ => () // Unknown item type, skip
    }
  }
  // Flush any remaining pending tool calls
  if pending_tool_calls.length() > 0 {
    messages.push(
      @types.ModelMessage::Assistant(
        content="",
        tool_calls=Some(pending_tool_calls),
      ),
    )
  }
  messages
}

///|
/// Extract text from content that can be either a plain string or
/// an array of content blocks (e.g. [{"type":"input_text","text":"..."}])
fn extract_text_content(content : Json) -> String {
  match content {
    String(s) => s
    Array(blocks) => {
      let buf = StringBuilder::new()
      for block in blocks {
        match block {
          // Responses API content block: {"type":"input_text","text":"..."}
          { "type": String("input_text"), "text": String(t), .. } =>
            buf.write_string(t)
          // Also handle {"type":"text","text":"..."} and {"type":"output_text","text":"..."}
          { "type": String("text"), "text": String(t), .. } =>
            buf.write_string(t)
          { "type": String("output_text"), "text": String(t), .. } =>
            buf.write_string(t)
          // Plain string in array
          String(t) => buf.write_string(t)
          _ => ()
        }
      }
      buf.to_string()
    }
    _ => ""
  }
}

///|
/// Extract multimodal content parts from content JSON.
/// Returns None for plain text, Some(parts) when non-text blocks are present.
/// Handles content formats from multiple APIs:
///   - OpenAI Responses API input types (input_text, input_image, input_audio, input_file)
///   - OpenAI Chat Completions content parts (text, image_url, input_audio, file)
///   - Anthropic content blocks (text, image, document)
fn extract_content_parts(content : Json) -> Array[@types.ContentPart]? {
  match content {
    String(_) => None
    Array(blocks) => {
      let parts : Array[@types.ContentPart] = []
      let mut has_non_text = false
      for block in blocks {
        match block {
          // Ref: OpenAI Responses API InputText — {"type":"input_text","text":"..."}
          { "type": String("input_text"), "text": String(t), .. } =>
            parts.push(@types.ContentPart::Text(t))
          // Ref: Anthropic TextBlockParam / OpenAI Chat text — {"type":"text","text":"..."}
          { "type": String("text"), "text": String(t), .. } =>
            parts.push(@types.ContentPart::Text(t))
          // Ref: OpenAI Responses API OutputText — {"type":"output_text","text":"..."}
          { "type": String("output_text"), "text": String(t), .. } =>
            parts.push(@types.ContentPart::Text(t))
          // Ref: OpenAI Responses API InputImage — {"type":"input_image","image_url":"...","detail":"auto"}
          { "type": String("input_image"), "image_url": String(url), .. } => {
            let detail = match block {
              { "detail": String(d), .. } => Some(d)
              _ => None
            }
            // data: URL → Base64, otherwise URL
            if url.has_prefix("data:") {
              match parse_data_url_simple(url) {
                Some((media_type, data)) => {
                  parts.push(
                    @types.ContentPart::ImageBase64(data~, media_type~),
                  )
                  has_non_text = true
                }
                None => ()
              }
            } else {
              parts.push(@types.ContentPart::ImageUrl(url~, detail~))
              has_non_text = true
            }
          }
          // Ref: OpenAI Chat ChatCompletionContentPartImage — {"type":"image_url","image_url":{"url":"...","detail":"auto"}}
          {
            "type": String("image_url"),
            "image_url": { "url": String(url), .. },
            ..
          } => {
            let detail = match block {
              { "image_url": { "detail": String(d), .. }, .. } => Some(d)
              _ => None
            }
            if url.has_prefix("data:") {
              match parse_data_url_simple(url) {
                Some((media_type, data)) => {
                  parts.push(
                    @types.ContentPart::ImageBase64(data~, media_type~),
                  )
                  has_non_text = true
                }
                None => ()
              }
            } else {
              parts.push(@types.ContentPart::ImageUrl(url~, detail~))
              has_non_text = true
            }
          }
          // Ref: OpenAI Responses API InputAudio — {"type":"input_audio","data":"...","format":"wav"}
          {
            "type": String("input_audio"),
            "data": String(data),
            "format": String(format),
            ..
          } => {
            parts.push(@types.ContentPart::Audio(data~, format~))
            has_non_text = true
          }
          // Ref: OpenAI Chat ChatCompletionContentPartInputAudio — {"type":"input_audio","input_audio":{"data":"...","format":"wav"}}
          {
            "type": String("input_audio"),
            "input_audio": {
              "data": String(data),
              "format": String(format),
              ..
            },
            ..
          } => {
            parts.push(@types.ContentPart::Audio(data~, format~))
            has_non_text = true
          }
          // Ref: OpenAI Chat file type (deprecated Sept 2025) — {"type":"file","file_id":"..."}
          // Still parsed for backward compatibility with older Chat API payloads
          { "type": String("file"), "file_id": String(file_id), .. } => {
            parts.push(@types.ContentPart::FileRef(file_id~, media_type=None))
            has_non_text = true
          }
          // Ref: Anthropic DocumentBlockParam (Base64) — {"type":"document","source":{"type":"base64","media_type":"...","data":"..."}}
          {
            "type": String("document"),
            "source": {
              "type": String("base64"),
              "media_type": String(media_type),
              "data": String(data),
              ..
            },
            ..
          } => {
            let title = match block {
              { "title": String(t), .. } => Some(t)
              _ => None
            }
            parts.push(@types.ContentPart::Document(data~, media_type~, title~))
            has_non_text = true
          }
          // Ref: OpenAI Responses API InputFile — {"type":"input_file","file_id":"file_..."}
          { "type": String("input_file"), "file_id": String(file_id), .. } => {
            parts.push(@types.ContentPart::FileRef(file_id~, media_type=None))
            has_non_text = true
          }
          // Ref: OpenAI Responses API InputFile with inline data — {"type":"input_file","file_data":"data:...;base64,..."}
          { "type": String("input_file"), "file_data": String(file_data), .. } =>
            // Parse data URL to extract media_type and data
            match parse_data_url_simple(file_data) {
              Some((media_type, data)) => {
                // Determine content type from media_type
                if media_type.has_prefix("video/") {
                  parts.push(@types.ContentPart::Video(data~, media_type~))
                } else {
                  // PDF, plain text, or other documents
                  let title = match block {
                    { "filename": String(f), .. } => Some(f)
                    _ => None
                  }
                  parts.push(
                    @types.ContentPart::Document(data~, media_type~, title~),
                  )
                }
                has_non_text = true
              }
              None => ()
            }
          // Ref: Anthropic DocumentBlockParam (File) — {"type":"document","source":{"type":"file","file_id":"..."}}
          {
            "type": String("document"),
            "source": { "type": String("file"), "file_id": String(file_id), .. },
            ..
          } => {
            parts.push(@types.ContentPart::FileRef(file_id~, media_type=None))
            has_non_text = true
          }
          // Plain string
          String(t) => parts.push(@types.ContentPart::Text(t))
          _ => ()
        }
      }
      // Only return parts if there are non-text parts
      if has_non_text {
        Some(parts)
      } else {
        None
      }
    }
    _ => None
  }
}

///|
/// Parse "data:image/png;base64,AAAA..." into (media_type, data)
fn parse_data_url_simple(url : String) -> (String, String)? {
  // data:media_type;base64,data
  if not(url.has_prefix("data:")) {
    return None
  }
  // Find semicolon and comma
  let mut semicolon_pos = -1
  let mut comma_pos = -1
  let mut i = 0
  for c in url {
    if c == ';' && semicolon_pos < 0 {
      semicolon_pos = i
    }
    if c == ',' && comma_pos < 0 {
      comma_pos = i
      break
    }
    i = i + 1
  }
  if semicolon_pos < 0 || comma_pos < 0 {
    return None
  }
  let media_type = url[5:semicolon_pos].to_string()
  let data = url[comma_pos + 1:].to_string()
  Some((media_type, data))
}

///|
fn json_array_to_strings(items : Array[Json]) -> Array[String] {
  let result : Array[String] = []
  for item in items {
    match item {
      String(value) => result.push(value)
      _ => ()
    }
  }
  result
}
