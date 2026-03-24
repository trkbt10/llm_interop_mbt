async fn run_openai_checks(
  opts : CliOptions,
  declared : Array[String],
  reports : Array[CheckReport],
  failures : Array[String],
) -> Unit {
  let check_names = [
    "openai.responses.stream.structured",
    "openai.responses.sync.structured",
    "openai.chat.sync.structured",
    "openai.responses.sync.json_object",
    "openai.responses.stream.json_object",
    "openai.chat.sync.json_object",
    "openai.responses.sync.file_url",
    "openai.responses.stream.file_url",
    "openai.responses.sync.file_data",
    "openai.responses.stream.file_data",
    "openai.chat.sync.file_data",
    "openai.responses.sync.file_id",
    "openai.responses.stream.file_id",
    "openai.chat.sync.file_id",
    "openai.responses.sync.toolcall.multiturn",
    "openai.responses.stream.toolcall.multiturn",
  ]
  register_checks(declared, check_names)
  if opts.list || not(any_selected_check(opts, check_names)) {
    return
  }
  let api_key = env("OPENAI_API_KEY")
  if api_key == "" {
    print_skip("openai", "OPENAI_API_KEY is not exported")
    return
  }
  let responses_provider = provider(
    "openai",
    @gateway.OpenAIResponses,
    api_key,
    "https://api.openai.com/v1",
  )
  let chat_provider = provider(
    "openai",
    @gateway.OpenAICompletions,
    api_key,
    "https://api.openai.com/v1",
  )
  let candidates = openai_stream_candidates()
  run_openai_response_format_checks(
    opts,
    reports,
    failures,
    responses_provider,
    chat_provider,
    candidates,
  )
  run_openai_file_checks(
    opts,
    reports,
    failures,
    api_key,
    responses_provider,
    chat_provider,
    candidates,
  )
  if should_run_check(opts, "openai.responses.sync.toolcall.multiturn") {
    let report = Some(
      run_tool_multiturn_sync_check(
        "openai.responses.sync.toolcall.multiturn",
        responses_provider,
        candidates,
        "openai-sync",
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("openai.responses.sync.toolcall.multiturn", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("openai.responses.sync.toolcall.multiturn", message)
        None
      }
    }
    match report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "openai.responses.stream.toolcall.multiturn") {
    let report = Some(
      run_tool_multiturn_stream_check(
        "openai.responses.stream.toolcall.multiturn",
        responses_provider,
        candidates,
        "openai-stream",
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("openai.responses.stream.toolcall.multiturn", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("openai.responses.stream.toolcall.multiturn", message)
        None
      }
    }
    match report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
}
