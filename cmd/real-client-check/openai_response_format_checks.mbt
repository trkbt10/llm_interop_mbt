///|
async fn run_openai_response_format_checks(
  opts : CliOptions,
  reports : Array[CheckReport],
  failures : Array[String],
  responses_provider : @gateway.ProviderConfig,
  chat_provider : @gateway.ProviderConfig,
  candidates : Array[String],
) -> Unit {
  if should_run_check(opts, "openai.responses.stream.structured") {
    let report = Some(
      run_stream_check(
        "openai.responses.stream.structured",
        responses_provider,
        candidates,
        structured_response_format(),
        validate_json_text_response,
        validate_openai_responses_carrier,
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("openai.responses.stream.structured", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("openai.responses.stream.structured", message)
        None
      }
    }
    match report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "openai.responses.sync.structured") {
    let report = Some(
      run_responses_sync_check(
        "openai.responses.sync.structured",
        responses_provider,
        candidates,
        structured_response_format(),
        validate_json_text_response,
        validate_openai_responses_carrier,
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("openai.responses.sync.structured", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("openai.responses.sync.structured", message)
        None
      }
    }
    match report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "openai.chat.sync.structured") {
    let report = Some(
      run_chat_check(
        "openai.chat.sync.structured",
        chat_provider,
        candidates,
        Some(structured_response_format()),
        structured_messages(),
        validate_json_text_response,
        validate_openai_chat_carrier,
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("openai.chat.sync.structured", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("openai.chat.sync.structured", message)
        None
      }
    }
    match report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "openai.responses.sync.json_object") {
    let report = Some(
      run_responses_sync_check(
        "openai.responses.sync.json_object",
        responses_provider,
        candidates,
        json_object_response_format(),
        validate_json_object_text_response,
        validate_openai_responses_json_object_carrier,
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("openai.responses.sync.json_object", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("openai.responses.sync.json_object", message)
        None
      }
    }
    match report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "openai.responses.stream.json_object") {
    let report = Some(
      run_stream_check(
        "openai.responses.stream.json_object",
        responses_provider,
        candidates,
        json_object_response_format(),
        validate_json_object_text_response,
        validate_openai_responses_json_object_carrier,
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("openai.responses.stream.json_object", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("openai.responses.stream.json_object", message)
        None
      }
    }
    match report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "openai.chat.sync.json_object") {
    let report = Some(
      run_chat_check(
        "openai.chat.sync.json_object",
        chat_provider,
        candidates,
        Some(json_object_response_format()),
        structured_messages(),
        validate_json_object_text_response,
        validate_openai_chat_json_object_carrier,
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("openai.chat.sync.json_object", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("openai.chat.sync.json_object", message)
        None
      }
    }
    match report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
}
