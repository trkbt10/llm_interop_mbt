///|
/// Whitebox tests for CLI selection and fixture report helpers.

///|
fn cleanup_real_client_check_tmp(dir : String) -> Unit {
  let file_path = dir + "/gateway.openai_to_anthropic.stream.toolcall.multiturn.json"
  @fs.remove_file(file_path) catch { _ => () }
  @fs.remove_dir(dir) catch { _ => () }
}

///|
test "real-client-check CLI parser handles filters, list mode, and fixture dir" {
  let opts = parse_real_client_check_args([
    "real-client-check",
    "--list",
    "--filter",
    "gateway.openai_to_anthropic.stream.toolcall.multiturn,gemini",
    "--fixtures-dir",
    "tmp-realcheck-fixtures",
  ])
  assert_true(opts.help == false)
  assert_true(opts.list)
  assert_eq(
    opts.filters,
    ["gateway.openai_to_anthropic.stream.toolcall.multiturn", "gemini"],
  )
  assert_eq(opts.fixtures_dir, Some("tmp-realcheck-fixtures"))
  assert_true(
    should_run_check(
      opts,
      "gateway.openai_to_anthropic.stream.toolcall.multiturn",
    ),
  )
  assert_true(should_run_check(opts, "gemini.responses.stream.structured"))
  assert_false(should_run_check(opts, "openai.responses.stream.structured"))
}

///|
test "real-client-check helpers register names and persist fixture reports" {
  let names : Array[String] = []
  register_checks(names, ["openai.responses.stream.structured", "gemini.responses.sync.structured"])
  register_checks(names, ["openai.responses.stream.structured"])
  assert_eq(
    names,
    ["openai.responses.stream.structured", "gemini.responses.sync.structured"],
  )
  let opts = {
    ..CliOptions::default(),
    fixtures_dir: Some("tmp_real_client_check_fixture"),
  }
  let dir = opts.fixtures_dir.unwrap_or("")
  cleanup_real_client_check_tmp(dir)
  let report : CheckReport = {
    name: "gateway.openai_to_anthropic.stream.toolcall.multiturn",
    model: "claude-sonnet-4-6",
    mode: "stream",
    request_url: "https://api.anthropic.com/v1/messages",
    carrier_summary: "toolcall followup anthropic tool_use_id mapped",
    event_types: ["response.output_item.done", "response.completed"],
    response_text: "{\"url\":\"https://example.com/interop-check\"}",
  }
  persist_check_report_if_configured(opts, report)

  let saved = @fs.read_file_to_string(
    dir + "/gateway.openai_to_anthropic.stream.toolcall.multiturn.json",
  ) catch {
    _ => fail("fixture report was not written")
  }
  assert_true(saved.contains("\"model\": \"claude-sonnet-4-6\""))
  assert_true(saved.contains("\"response_text\":"))
  cleanup_real_client_check_tmp(dir)
}

///|
test "build_openai_surface_stream_request uses Gemini stream endpoint for tool translation" {
  let req = build_openai_surface_stream_request(
    provider(
      "gemini",
      @gateway.GoogleGenerativeAI,
      "gemini-key",
      "https://generativelanguage.googleapis.com/v1beta",
    ),
    raw_openai_surface_tool_body(
      "gemini-2.0-flash",
      tool_turn_one_messages("gateway-gemini-stream"),
      None,
      Some(openai_function_tool_choice("lookup_verification_url")),
    ),
    "gemini-2.0-flash",
  )
  let body = req.body.unwrap_or("")
  assert_true(
    req.url.contains(
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:streamGenerateContent?alt=sse&key=gemini-key",
    ),
  )
  assert_false(body.contains("\"stream\":true"))
  assert_true(body.contains("\"functionDeclarations\""))
  assert_true(body.contains("gateway-gemini-stream"))
}

///|
test "build_openai_surface_stream_request uses Gemini stream endpoint for structured translation" {
  let req = build_openai_surface_stream_request(
    provider(
      "gemini",
      @gateway.GoogleGenerativeAI,
      "gemini-key",
      "https://generativelanguage.googleapis.com/v1beta",
    ),
    raw_openai_surface_translation_body(
      "gemini-2.0-flash",
      structured_response_format(),
    ),
    "gemini-2.0-flash",
  )
  let body = req.body.unwrap_or("")
  assert_true(req.url.contains(":streamGenerateContent?alt=sse&key=gemini-key"))
  assert_false(body.contains("\"stream\":true"))
  assert_true(body.contains("\"systemInstruction\""))
  assert_true(body.contains("\"responseMimeType\":\"application/json\""))
  assert_true(body.contains("\"responseJsonSchema\""))
}

///|
test "openai file upload body encodes purpose and file payload" {
  let body = build_openai_file_upload_body(
    "boundary-1",
    "company.txt",
    "text/plain",
    "Berkshire Hathaway",
  )
  assert_true(body.contains("name=\"purpose\""))
  assert_true(body.contains("\r\n\r\nuser_data\r\n"))
  assert_true(body.contains("filename=\"company.txt\""))
  assert_true(body.contains("Content-Type: text/plain"))
  assert_true(body.contains("Berkshire Hathaway"))
}

///|
test "file input message helpers keep document and file ref carriers distinct" {
  match file_data_messages() {
    [
      @types.ModelMessage::User(content_parts=Some(parts), ..),
    ] => {
      assert_eq(parts.length(), 2)
      assert_true(parts[1] is @types.ContentPart::Document(..))
    }
    _ => fail("Expected file_data message")
  }
  match file_id_messages("file_123") {
    [
      @types.ModelMessage::User(content_parts=Some(parts), ..),
    ] => {
      assert_eq(parts.length(), 2)
      assert_true(parts[1] is @types.ContentPart::FileRef(..))
    }
    _ => fail("Expected file_id message")
  }
}
