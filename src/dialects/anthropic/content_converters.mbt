///|
/// Content conversion utilities
/// Handles conversion of images, tool results, and complex content between providers

// =============================================================================
// Image Conversion (Claude -> Responses API)
// =============================================================================

///|
/// Convert Claude image block to Responses API input_image format
/// Handles both base64 and URL sources
pub fn convert_claude_image_to_responses(image : Json) -> Json {
  match image {
    { "type": String("image"), "source": source, .. } =>
      match source {
        // Base64 encoded image
        {
          "type": String("base64"),
          "data": String(data),
          "media_type": String(media_type),
          ..
        } =>
          {
            "type": "input_image",
            "image_url": "data:\{media_type};base64,\{data}",
            "detail": "auto",
          }
        // URL image reference
        { "type": String("url"), "url": String(url), .. } =>
          { "type": "input_image", "image_url": url, "detail": "auto" }
        _ =>
          abort(
            "Claude image block must contain a supported source: " +
            image.stringify(),
          )
      }
    _ => abort("Expected Claude image block: " + image.stringify())
  }
}

///|
/// Check if a content block is an image block
pub fn is_image_block(block : Json) -> Bool {
  match block {
    { "type": String("image"), .. } => true
    _ => false
  }
}

// =============================================================================
// Tool Result Conversion (Claude -> Responses API)
// =============================================================================

///|
/// Convert Claude tool_result to Responses API function_call_output
pub fn convert_claude_tool_result_to_responses(block : Json) -> Json {
  match block {
    {
      "type": String("tool_result"),
      "tool_use_id": String(tool_use_id),
      "content": content,
      ..
    } => {
      let call_id = @interop_util.anthropic_to_openai_chat_call_id(tool_use_id)
      let id = @interop_util.anthropic_to_openai_responses_call_id(tool_use_id)
      let output = match content {
        String(s) => s
        _ => content.stringify()
      }
      {
        "id": id,
        "type": "function_call_output",
        "call_id": call_id,
        "output": output,
      }
    }
    _ => abort("Expected Claude tool_result block: " + block.stringify())
  }
}

///|
/// Check if a content block is a tool result
pub fn is_tool_result_block(block : Json) -> Bool {
  match block {
    { "type": String("tool_result"), .. } => true
    _ => false
  }
}

// =============================================================================
// Tool Use Conversion (Claude -> Responses API)
// =============================================================================

///|
/// Convert Claude tool_use to Responses API function_call
pub fn convert_claude_tool_use_to_responses(block : Json) -> Json {
  match block {
    {
      "type": String("tool_use"),
      "id": String(id),
      "name": String(name),
      "input": input,
      ..
    } => {
      let call_id = @interop_util.anthropic_to_openai_responses_call_id(id)
      {
        "type": "function_call",
        "id": call_id,
        "call_id": call_id,
        "name": name,
        "arguments": input.stringify(),
        "status": "completed",
      }
    }
    _ => abort("Expected Claude tool_use block: " + block.stringify())
  }
}

///|
/// Check if a content block is a tool use
pub fn is_tool_use_block(block : Json) -> Bool {
  match block {
    { "type": String("tool_use"), .. } => true
    _ => false
  }
}

// =============================================================================
// Text Content Conversion
// =============================================================================

///|
/// Convert Claude text block to Responses API output_text
pub fn convert_claude_text_to_responses(block : Json) -> Json {
  match block {
    { "type": String("text"), "text": String(text), .. } =>
      { "type": "output_text", "text": text }
    _ => abort("Expected Claude text block: " + block.stringify())
  }
}

///|
/// Check if a content block is a text block
pub fn is_text_block(block : Json) -> Bool {
  match block {
    { "type": String("text"), .. } => true
    _ => false
  }
}

// =============================================================================
// Responses API -> Claude Conversion
// =============================================================================

///|
/// Convert Responses API function_call to Claude tool_use
pub fn convert_responses_function_call_to_claude(block : Json) -> Json {
  match block {
    {
      "type": String("function_call"),
      "name": String(name),
      "arguments": String(args),
      ..
    } => {
      let id = convert_responses_function_call_id_to_claude(block)
      let input = parse_responses_tool_arguments_or_abort(args, block)
      { "type": "tool_use", "id": id, "name": name, "input": input }
    }
    { "type": String("web_search_call"), "id": String(id), .. } => {
      let input = match block {
        { "action": { "query": String(query), .. }, .. } => { "query": query }
        _ =>
          abort(
            "Responses web_search_call is missing required action.query: " +
            block.stringify(),
          )
      }
      {
        "type": "tool_use",
        "id": @interop_util.openai_responses_to_anthropic_tool_use_id(id),
        "name": @types.web_search_tool_name(),
        "input": input,
      }
    }
    _ =>
      abort(
        "Expected Responses function_call/web_search_call block: " +
        block.stringify(),
      )
  }
}

///|
/// Convert Responses API function_call_output to Claude tool_result
pub fn convert_responses_function_call_output_to_claude(block : Json) -> Json {
  match block {
    {
      "type": String("function_call_output"),
      "call_id": String(call_id),
      "output": String(output),
      ..
    } => {
      let tool_use_id = @interop_util.openai_responses_to_anthropic_tool_use_id(
        call_id,
      )
      { "type": "tool_result", "tool_use_id": tool_use_id, "content": output }
    }
    _ =>
      abort(
        "Expected Responses function_call_output block: " + block.stringify(),
      )
  }
}

///|
/// Convert Responses API input_image to Claude image block
pub fn convert_responses_image_to_claude(block : Json) -> Json {
  match block {
    { "type": String("input_image"), "image_url": String(url), .. } =>
      if url.has_prefix("data:") {
        // Parse data URI: data:media_type;base64,data
        let without_prefix = url[5:].to_string() // Remove "data:"
        let semicolon_idx = find_char(without_prefix, ';')
        if semicolon_idx >= 0 {
          let media_type = without_prefix[:semicolon_idx].to_string()
          let rest = without_prefix[semicolon_idx + 1:].to_string()
          if rest.has_prefix("base64,") {
            let data = rest[7:].to_string()
            return {
              "type": "image",
              "source": {
                "type": "base64",
                "media_type": media_type,
                "data": data,
              },
            }
          }
        }
        { "type": "image", "source": { "type": "url", "url": url } }
      } else {
        { "type": "image", "source": { "type": "url", "url": url } }
      }
    _ => abort("Expected Responses input_image block: " + block.stringify())
  }
}

///|
fn convert_responses_function_call_id_to_claude(block : Json) -> String {
  match block {
    { "call_id": String(cid), .. } =>
      @interop_util.openai_responses_to_anthropic_tool_use_id(cid)
    { "id": String(fid), .. } =>
      @interop_util.openai_responses_to_anthropic_tool_use_id(fid)
    _ =>
      abort(
        "Responses function_call is missing required id/call_id: " +
        block.stringify(),
      )
  }
}

///|
fn parse_responses_tool_arguments_or_abort(args : String, block : Json) -> Json {
  @json.parse(args) catch {
    _ =>
      abort(
        "Responses function_call arguments must be valid JSON: " +
        block.stringify(),
      )
  }
}

///|
/// Find the index of a character in a string
fn find_char(s : String, c : Char) -> Int {
  let chars = s.iter().collect()
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == c {
      return i
    }
  }
  -1
}
