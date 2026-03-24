async fn run_gemini_check(
  opts : CliOptions,
  declared : Array[String],
  reports : Array[CheckReport],
  failures : Array[String],
) -> Unit {
  let check_names = [
    "gemini.responses.stream.structured",
    "gemini.responses.sync.structured",
    "gemini.responses.sync.json_object",
    "gemini.responses.stream.json_object",
    "gemini.responses.sync.toolcall.multiturn",
    "gateway.openai_to_gemini.sync.structured",
    "gateway.openai_to_gemini.sync.json_object",
    "gateway.openai_to_gemini.stream.structured",
    "gateway.openai_to_gemini.stream.json_object",
    "gateway.openai_to_gemini.sync.toolcall.multiturn",
    "gateway.openai_to_gemini.stream.toolcall.multiturn",
    "gemini.responses.stream.toolcall.multiturn",
  ]
  register_checks(declared, check_names)
  if opts.list || not(any_selected_check(opts, check_names)) {
    return
  }
  let api_key = env("GEMINI_API_KEY")
  if api_key == "" {
    print_skip("gemini", "GEMINI_API_KEY is not exported")
    return
  }
  let provider = provider(
    "gemini",
    @gateway.GoogleGenerativeAI,
    api_key,
    "https://generativelanguage.googleapis.com/v1beta",
  )
  if should_run_check(opts, "gemini.responses.stream.structured") {
    let report = Some(
      run_stream_check(
        "gemini.responses.stream.structured",
        provider,
        gemini_candidates(),
        structured_response_format(),
        validate_json_text_response,
        validate_gemini_carrier,
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("gemini.responses.stream.structured", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("gemini.responses.stream.structured", message)
        None
      }
    }
    match report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "gemini.responses.sync.structured") {
    let sync_structured_report = Some(
      run_responses_sync_check(
        "gemini.responses.sync.structured",
        provider,
        gemini_candidates(),
        structured_response_format(),
        validate_json_text_response,
        validate_gemini_carrier,
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("gemini.responses.sync.structured", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("gemini.responses.sync.structured", message)
        None
      }
    }
    match sync_structured_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "gemini.responses.sync.json_object") {
    let json_object_sync_report = Some(
      run_responses_sync_check(
        "gemini.responses.sync.json_object",
        provider,
        gemini_candidates(),
        json_object_response_format(),
        validate_json_object_text_response,
        validate_gemini_json_object_carrier,
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("gemini.responses.sync.json_object", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("gemini.responses.sync.json_object", message)
        None
      }
    }
    match json_object_sync_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "gemini.responses.stream.json_object") {
    let json_object_stream_report = Some(
      run_stream_check(
        "gemini.responses.stream.json_object",
        provider,
        gemini_candidates(),
        json_object_response_format(),
        validate_json_object_text_response,
        validate_gemini_json_object_carrier,
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("gemini.responses.stream.json_object", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("gemini.responses.stream.json_object", message)
        None
      }
    }
    match json_object_stream_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "gemini.responses.sync.toolcall.multiturn") {
    let tool_sync_report = Some(
      run_tool_multiturn_sync_check(
        "gemini.responses.sync.toolcall.multiturn",
        provider,
        gemini_candidates(),
        "gemini-sync",
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("gemini.responses.sync.toolcall.multiturn", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("gemini.responses.sync.toolcall.multiturn", message)
        None
      }
    }
    match tool_sync_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "gateway.openai_to_gemini.sync.structured") {
    let translated_report = Some(
      run_openai_surface_translation_check(
        "gateway.openai_to_gemini.sync.structured",
        provider,
        gemini_candidates(),
        structured_response_format(),
        validate_json_text_response,
        validate_gateway_openai_to_gemini_carrier,
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("gateway.openai_to_gemini.sync.structured", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("gateway.openai_to_gemini.sync.structured", message)
        None
      }
    }
    match translated_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "gateway.openai_to_gemini.sync.json_object") {
    let translated_json_object_report = Some(
      run_openai_surface_translation_check(
        "gateway.openai_to_gemini.sync.json_object",
        provider,
        gemini_candidates(),
        json_object_response_format(),
        validate_json_object_text_response,
        validate_gateway_openai_to_gemini_json_object_carrier,
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("gateway.openai_to_gemini.sync.json_object", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("gateway.openai_to_gemini.sync.json_object", message)
        None
      }
    }
    match translated_json_object_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "gateway.openai_to_gemini.stream.structured") {
    let translated_stream_report = Some(
      run_openai_surface_stream_translation_check(
        "gateway.openai_to_gemini.stream.structured",
        provider,
        gemini_candidates(),
        structured_response_format(),
        validate_json_text_response,
        validate_gateway_openai_to_gemini_carrier,
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("gateway.openai_to_gemini.stream.structured", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("gateway.openai_to_gemini.stream.structured", message)
        None
      }
    }
    match translated_stream_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "gateway.openai_to_gemini.stream.json_object") {
    let translated_json_object_stream_report = Some(
      run_openai_surface_stream_translation_check(
        "gateway.openai_to_gemini.stream.json_object",
        provider,
        gemini_candidates(),
        json_object_response_format(),
        validate_json_object_text_response,
        validate_gateway_openai_to_gemini_json_object_carrier,
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("gateway.openai_to_gemini.stream.json_object", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("gateway.openai_to_gemini.stream.json_object", message)
        None
      }
    }
    match translated_json_object_stream_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "gateway.openai_to_gemini.sync.toolcall.multiturn") {
    let translated_tool_report = Some(
      run_openai_surface_tool_translation_check(
        "gateway.openai_to_gemini.sync.toolcall.multiturn",
        provider,
        gemini_candidates(),
        "gateway-gemini-sync",
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("gateway.openai_to_gemini.sync.toolcall.multiturn", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("gateway.openai_to_gemini.sync.toolcall.multiturn", message)
        None
      }
    }
    match translated_tool_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "gateway.openai_to_gemini.stream.toolcall.multiturn") {
    let translated_tool_stream_report = Some(
      run_openai_surface_tool_translation_stream_check(
        "gateway.openai_to_gemini.stream.toolcall.multiturn",
        provider,
        gemini_candidates(),
        "gateway-gemini-stream",
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure(
          "gateway.openai_to_gemini.stream.toolcall.multiturn",
          message,
        )
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure(
          "gateway.openai_to_gemini.stream.toolcall.multiturn",
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
  if should_run_check(opts, "gemini.responses.stream.toolcall.multiturn") {
    let tool_stream_report = Some(
      run_tool_multiturn_stream_check(
        "gemini.responses.stream.toolcall.multiturn",
        provider,
        gemini_candidates(),
        "gemini-stream",
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("gemini.responses.stream.toolcall.multiturn", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("gemini.responses.stream.toolcall.multiturn", message)
        None
      }
    }
    match tool_stream_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
}

///|
