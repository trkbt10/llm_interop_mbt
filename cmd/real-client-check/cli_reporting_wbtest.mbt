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
