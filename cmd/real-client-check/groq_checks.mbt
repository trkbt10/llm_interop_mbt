async fn run_groq_check(
  opts : CliOptions,
  declared : Array[String],
  reports : Array[CheckReport],
  failures : Array[String],
) -> Unit {
  let check_names = ["groq.chat.sync.json_object", "groq.chat.sync.basic"]
  register_checks(declared, check_names)
  if opts.list || not(any_selected_check(opts, check_names)) {
    return
  }
  let api_key = env("GROQ_API_KEY")
  if api_key == "" {
    print_skip("groq", "GROQ_API_KEY is not exported")
    return
  }
  let provider = provider(
    "groq",
    @gateway.OpenAICompletions,
    api_key,
    "https://api.groq.com/openai/v1",
  )
  let wants_json_object = should_run_check(opts, "groq.chat.sync.json_object")
  let wants_basic = should_run_check(opts, "groq.chat.sync.basic")
  if not(wants_json_object) && wants_basic {
    let basic_report = run_chat_check(
      "groq.chat.sync.basic",
      provider,
      groq_candidates(),
      None,
      basic_messages(),
      validate_exact_ok,
      validate_basic_carrier,
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("groq.chat.sync.basic", message)
        return
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("groq.chat.sync.basic", message)
        return
      }
    }
    record_check_success(opts, reports, basic_report)
    return
  }
  if not(wants_json_object) {
    return
  }
  let structured_report = run_chat_check(
    "groq.chat.sync.json_object",
    provider,
    groq_candidates(),
    Some(json_object_response_format()),
    structured_messages(),
    validate_json_text_response,
    validate_groq_json_object_carrier,
  ) catch {
    ValidationFailed(message) => {
      failures.push(message)
      print_failure("groq.chat.sync.json_object", message)
      return
    }
    ModelUnavailable(message) => {
      failures.push(message)
      print_failure("groq.chat.sync.json_object", message)
      return
    }
  }
  record_check_success(opts, reports, structured_report)
}

///|
