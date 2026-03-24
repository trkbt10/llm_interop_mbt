async fn run_anthropic_check(
  opts : CliOptions,
  declared : Array[String],
  reports : Array[CheckReport],
  failures : Array[String],
) -> Unit {
  let check_names = [
    "anthropic.responses.stream.structured",
    "anthropic.responses.sync.structured",
    "anthropic.responses.sync.json_object",
    "anthropic.responses.stream.json_object",
    "anthropic.responses.sync.toolcall.multiturn",
    "anthropic.responses.stream.toolcall.multiturn",
    "gateway.openai_to_anthropic.sync.structured",
    "gateway.openai_to_anthropic.sync.json_object",
    "gateway.openai_to_anthropic.stream.structured",
    "gateway.openai_to_anthropic.stream.json_object",
    "gateway.openai_to_anthropic.sync.toolcall.multiturn",
    "gateway.openai_to_anthropic.stream.toolcall.multiturn",
  ]
  register_checks(declared, check_names)
  if opts.list || not(any_selected_check(opts, check_names)) {
    return
  }
  let api_key = env("ANTHROPIC_API_KEY")
  if api_key == "" {
    print_skip("anthropic", "ANTHROPIC_API_KEY is not exported")
    return
  }
  let provider = provider(
    "anthropic",
    @gateway.AnthropicMessages,
    api_key,
    "https://api.anthropic.com/v1",
  )
  let candidates = anthropic_candidates(api_key)
  if should_run_check(opts, "anthropic.responses.stream.structured") {
    let report = Some(
      run_stream_check(
        "anthropic.responses.stream.structured",
        provider,
        candidates,
        structured_response_format(),
        validate_json_text_response,
        validate_anthropic_carrier,
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("anthropic.responses.stream.structured", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("anthropic.responses.stream.structured", message)
        None
      }
    }
    match report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "anthropic.responses.sync.structured") {
    let sync_structured_report = Some(
      run_responses_sync_check(
        "anthropic.responses.sync.structured",
        provider,
        candidates,
        structured_response_format(),
        validate_json_text_response,
        validate_anthropic_carrier,
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("anthropic.responses.sync.structured", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("anthropic.responses.sync.structured", message)
        None
      }
    }
    match sync_structured_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "anthropic.responses.sync.json_object") {
    let json_object_sync_report = Some(
      run_responses_sync_check(
        "anthropic.responses.sync.json_object",
        provider,
        candidates,
        json_object_response_format(),
        validate_json_object_text_response,
        validate_anthropic_json_object_carrier,
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("anthropic.responses.sync.json_object", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("anthropic.responses.sync.json_object", message)
        None
      }
    }
    match json_object_sync_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "anthropic.responses.stream.json_object") {
    let json_object_stream_report = Some(
      run_stream_check(
        "anthropic.responses.stream.json_object",
        provider,
        candidates,
        json_object_response_format(),
        validate_json_object_text_response,
        validate_anthropic_json_object_carrier,
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("anthropic.responses.stream.json_object", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("anthropic.responses.stream.json_object", message)
        None
      }
    }
    match json_object_stream_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "anthropic.responses.sync.toolcall.multiturn") {
    let tool_sync_report = Some(
      run_tool_multiturn_sync_check(
        "anthropic.responses.sync.toolcall.multiturn",
        provider,
        candidates,
        "anthropic-sync",
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("anthropic.responses.sync.toolcall.multiturn", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("anthropic.responses.sync.toolcall.multiturn", message)
        None
      }
    }
    match tool_sync_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "anthropic.responses.stream.toolcall.multiturn") {
    let tool_stream_report = Some(
      run_tool_multiturn_stream_check(
        "anthropic.responses.stream.toolcall.multiturn",
        provider,
        candidates,
        "anthropic-stream",
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("anthropic.responses.stream.toolcall.multiturn", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("anthropic.responses.stream.toolcall.multiturn", message)
        None
      }
    }
    match tool_stream_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "gateway.openai_to_anthropic.sync.structured") {
    let translated_report = Some(
      run_openai_surface_translation_check(
        "gateway.openai_to_anthropic.sync.structured",
        provider,
        candidates,
        structured_response_format(),
        validate_json_text_response,
        validate_gateway_openai_to_anthropic_carrier,
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("gateway.openai_to_anthropic.sync.structured", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("gateway.openai_to_anthropic.sync.structured", message)
        None
      }
    }
    match translated_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "gateway.openai_to_anthropic.sync.json_object") {
    let translated_json_object_report = Some(
      run_openai_surface_translation_check(
        "gateway.openai_to_anthropic.sync.json_object",
        provider,
        candidates,
        json_object_response_format(),
        validate_json_object_text_response,
        validate_gateway_openai_to_anthropic_json_object_carrier,
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("gateway.openai_to_anthropic.sync.json_object", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("gateway.openai_to_anthropic.sync.json_object", message)
        None
      }
    }
    match translated_json_object_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "gateway.openai_to_anthropic.stream.structured") {
    let translated_stream_report = Some(
      run_openai_surface_stream_translation_check(
        "gateway.openai_to_anthropic.stream.structured",
        provider,
        candidates,
        structured_response_format(),
        validate_json_text_response,
        validate_gateway_openai_to_anthropic_carrier,
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("gateway.openai_to_anthropic.stream.structured", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("gateway.openai_to_anthropic.stream.structured", message)
        None
      }
    }
    match translated_stream_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "gateway.openai_to_anthropic.stream.json_object") {
    let translated_json_object_stream_report = Some(
      run_openai_surface_stream_translation_check(
        "gateway.openai_to_anthropic.stream.json_object",
        provider,
        candidates,
        json_object_response_format(),
        validate_json_object_text_response,
        validate_gateway_openai_to_anthropic_json_object_carrier,
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("gateway.openai_to_anthropic.stream.json_object", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("gateway.openai_to_anthropic.stream.json_object", message)
        None
      }
    }
    match translated_json_object_stream_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "gateway.openai_to_anthropic.sync.toolcall.multiturn") {
    let translated_tool_report = Some(
      run_openai_surface_tool_translation_check(
        "gateway.openai_to_anthropic.sync.toolcall.multiturn",
        provider,
        candidates,
        "gateway-anthropic-sync",
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("gateway.openai_to_anthropic.sync.toolcall.multiturn", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("gateway.openai_to_anthropic.sync.toolcall.multiturn", message)
        None
      }
    }
    match translated_tool_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "gateway.openai_to_anthropic.stream.toolcall.multiturn") {
    let translated_tool_stream_report = Some(
      run_openai_surface_tool_translation_stream_check(
        "gateway.openai_to_anthropic.stream.toolcall.multiturn",
        provider,
        candidates,
        "gateway-anthropic-stream",
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure(
          "gateway.openai_to_anthropic.stream.toolcall.multiturn",
          message,
        )
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure(
          "gateway.openai_to_anthropic.stream.toolcall.multiturn",
          message,
        )
        None
      }
    }
    match translated_tool_stream_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
}

///|
