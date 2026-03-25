fn extract_response_text(response : @types.ModelResponse) -> String raise LiveCheckError {
  match response.as_failure() {
    Some(failure) =>
      match failure.retry_after {
        Some(retry_after) if failure.type_ == "rate_limit_error" =>
          raise ModelUnavailable("rate limited: retry_after=\{retry_after}")
        _ =>
          raise ValidationFailed(
            "model failure response [\{failure.type_}]: " + failure.message,
          )
      }
    None => ()
  }
  match response {
    @types.ModelResponse::Text(text) => text
    @types.ModelResponse::RichText(rich) => rich.content
    @types.ModelResponse::ToolCallsWithContent(rich~, ..) => rich.content
    @types.ModelResponse::ToolCalls(calls) =>
      raise ValidationFailed(
        "unexpected tool-only response: " + calls.map(fn(call) {
          "\{call.id}:\{call.name}:\{call.arguments.stringify()}"
        }).join(" | "),
      )
    _ => raise ValidationFailed("unreachable non-text response variant")
  }
}

///|
fn validate_json_url(text : String) -> String raise LiveCheckError {
  validate_json_url_against(text, expected_url)
}

///|
fn validate_json_url_against(
  text : String,
  expected : String,
) -> String raise LiveCheckError {
  let trimmed = text.trim(chars=" \n\r\t").to_string()
  let json = @json.parse(trimmed) catch {
    _ => raise ValidationFailed("response was not valid JSON: " + trimmed)
  }
  match json {
    { "url": String(url), .. } => {
      if url != expected {
        raise ValidationFailed(
          "unexpected url value: " + url + " in " + trimmed,
        )
      }
      url
    }
    _ => raise ValidationFailed(
      "response JSON did not contain $.url: " + trimmed,
    )
  }
}

///|
fn validate_tool_json_url_against(
  text : String,
  expected : String,
) -> String raise LiveCheckError {
  validate_json_url_against(text, expected)
}

///|
fn tool_followup_response_format(
  api : @gateway.ModelApi,
) -> @types.ResponseFormat? {
  match api {
    @gateway.GoogleGenerativeAI => None
    _ => Some(structured_response_format())
  }
}

///|
fn validate_exact_ok(text : String) -> Unit raise LiveCheckError {
  let trimmed = text.trim(chars=" \n\r\t").to_string()
  if trimmed != "OK" {
    raise ValidationFailed("unexpected text response: " + trimmed)
  }
}

///|
fn summarize_events(events : Array[String]) -> Array[String] {
  if events.length() <= 8 {
    return events
  }
  events[events.length() - 8:].to_array()
}

///|
fn validate_stream_events(events : Array[String]) -> Unit raise LiveCheckError {
  if not(events.contains("response.output_text.delta")) {
    raise ValidationFailed("missing response.output_text.delta event")
  }
  if not(events.contains("response.completed")) {
    raise ValidationFailed("missing response.completed event")
  }
}

///|
fn validate_tool_stream_events(events : Array[String]) -> Unit raise LiveCheckError {
  if not(events.contains("response.completed")) {
    raise ValidationFailed("missing response.completed event")
  }
  if not(
    events.contains("response.output_item.added") ||
    events.contains("response.output_item.done") ||
      events.contains("response.function_call_arguments.delta") ||
      events.contains("response.function_call_arguments.done")
  ) {
    raise ValidationFailed("missing tool-call stream event: " + events.join(","))
  }
}

///|
fn validate_json_text_response(text : String) -> Unit raise LiveCheckError {
  ignore(validate_json_url(text))
}

///|
fn validate_json_object_text_response(text : String) -> Unit raise LiveCheckError {
  let json = @json.parse(text) catch {
    err =>
      raise ValidationFailed("response was not valid JSON object text: " + err.to_string())
  }
  match json {
    Object(_) => ()
    _ => raise ValidationFailed("response was not a JSON object: " + text)
  }
}

///|
fn validate_company_response(text : String) -> Unit raise LiveCheckError {
  let trimmed = text.trim(chars=" \n\r\t").to_string()
  let json = @json.parse(trimmed) catch {
    _ => raise ValidationFailed("response was not valid JSON: " + trimmed)
  }
  match json {
    { "company": String(company), .. } if company == expected_company => ()
    { "company": String(company), .. } =>
      raise ValidationFailed(
        "unexpected company value: " + company + " in " + trimmed,
      )
    _ =>
      raise ValidationFailed(
        "response JSON did not contain $.company: " + trimmed,
      )
  }
}

///|
fn validate_basic_carrier(body : String) -> String raise LiveCheckError {
  if body == "__never__" {
    raise ValidationFailed("unreachable basic carrier sentinel")
  }
  "groq:chat basic"
}

///|
