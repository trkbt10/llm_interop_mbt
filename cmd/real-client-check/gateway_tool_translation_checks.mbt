async fn attempt_openai_surface_tool_translation_model(
  name : String,
  provider : @gateway.ProviderConfig,
  model : String,
  label : String,
) -> CheckReport raise LiveCheckError {
  let base_url = if provider.base_url.is_empty() {
    provider.api.default_base_url()
  } else {
    provider.base_url
  }
  let mut messages = tool_turn_one_messages(label)
  let mut request_url = ""
  let mut last_request_body = ""
  let mut last_response_body = ""
  let mut carrier_summary = ""
  let mut saw_tool_call = false
  let mut pending_call_id = ""
  for _ in 0..<4 {
    let source_body = raw_openai_surface_tool_body(
      model,
      messages,
      if saw_tool_call { tool_followup_response_format(provider.api) } else { None },
      if saw_tool_call {
        Some(Json::string("none"))
      } else {
        Some(openai_function_tool_choice("lookup_verification_url"))
      },
    )
    let upstream = @gateway.prepare_upstream(
      provider,
      source_body,
      @gateway.OpenAI,
      model,
      base_url,
      provider.api_key,
    )
    let transport = NativeHttpTransport::new()
    let resp = transport.request(build_gateway_transport_request(upstream)) catch {
      @client.TransportError::NetworkError(msg) =>
        raise ValidationFailed(name + ": http transport " + msg)
      @client.TransportError::TimeoutError =>
        raise ValidationFailed(name + ": http transport timeout")
    }
    request_url = transport.last_url
    last_request_body = transport.last_body
    last_response_body = transport.last_response_body
    if pending_call_id.length() > 0 {
      carrier_summary =
        "gateway openai->" +
        tool_followup_carrier_summary(
          provider.api,
          last_request_body,
          pending_call_id,
        )
      pending_call_id = ""
    }
    if resp.status < 200 || resp.status >= 300 {
      let trimmed_message = resp.body.trim(chars=" \n\r\t").to_string()
      if is_retryable_model_error(resp.status, trimmed_message) {
        raise ModelUnavailable(
          model + ": api " + resp.status.to_string() + " " + trimmed_message,
        )
      } else {
        raise ValidationFailed(
          name + ": api " + resp.status.to_string() + " " + resp.body,
        )
      }
    }
    let translated = @gateway.transform_response(
      resp.body,
      provider.api.to_dialect(),
      @gateway.OpenAI,
    )
    let response = parse_translated_openai_response(translated)
    match response {
      @types.ModelResponse::ToolCalls(_)
      | @types.ModelResponse::ToolCallsWithContent(..) => {
        let extracted = extract_tool_call(response) catch {
          ValidationFailed(message) =>
            raise ValidationFailed(
              message +
                "\nrequest=" + last_request_body +
                "\nresponse=" + last_response_body +
                "\ntranslated=" + translated,
            )
          ModelUnavailable(message) => raise ModelUnavailable(message)
        }
        validate_extracted_tool_call(extracted, label)
        saw_tool_call = true
        messages = append_tool_followup_messages(messages, label, extracted)
        pending_call_id = extracted.call.id
      }
      _ => {
        if not(saw_tool_call) {
          raise ValidationFailed(
            "expected tool call response" +
              "\nrequest=" + last_request_body +
              "\nresponse=" + last_response_body +
              "\ntranslated=" + translated,
          )
        }
        let text = extract_response_text(response) catch {
          ValidationFailed(message) =>
            raise ValidationFailed(
              message +
                "\nrequest=" + last_request_body +
                "\nresponse=" + last_response_body +
                "\ntranslated=" + translated,
            )
          ModelUnavailable(message) => raise ModelUnavailable(message)
        }
        ignore(
          validate_tool_json_url_against(
            text,
            expected_tool_url(label),
          ),
        )
        return {
          name,
          model,
          mode: "sync",
          request_url,
          carrier_summary,
          event_types: [],
          response_text: text.trim(chars=" \n\r\t").to_string(),
        }
      }
    }
  }
  raise ValidationFailed(
    name + ": translated tool conversation did not converge" +
      "\nrequest=" + last_request_body +
      "\nresponse=" + last_response_body,
  )
}

///|
async fn run_openai_surface_tool_translation_check(
  name : String,
  provider : @gateway.ProviderConfig,
  candidates : Array[String],
  label : String,
) -> CheckReport raise LiveCheckError {
  let attempts : Array[String] = []
  for model in candidates {
    let report = attempt_openai_surface_tool_translation_model(
      name,
      provider,
      model,
      label,
    ) catch {
      ModelUnavailable(message) => {
        attempts.push(message)
        continue
      }
      ValidationFailed(message) => raise ValidationFailed(message)
    }
    return report
  }
  let attempted = attempts.join(" | ")
  raise ValidationFailed(
    name + ": no working model candidate. tried=" + attempted,
  )
}

///|
async fn attempt_openai_surface_tool_translation_stream_model(
  name : String,
  provider : @gateway.ProviderConfig,
  model : String,
  label : String,
) -> CheckReport raise LiveCheckError {
  let mut messages = tool_turn_one_messages(label)
  let mut request_url = ""
  let mut carrier_summary = ""
  let mut last_request_body = ""
  let mut saw_tool_call = false
  let mut pending_call_id = ""
  let all_events : Array[String] = []
  for _ in 0..<4 {
    let req = build_openai_surface_stream_request(
      provider,
      raw_openai_surface_tool_body(
        model,
        messages,
        if saw_tool_call { tool_followup_response_format(provider.api) } else { None },
        if saw_tool_call {
          Some(Json::string("none"))
        } else {
          Some(openai_function_tool_choice("lookup_verification_url"))
        },
      ),
      model,
    )
    let transport = NativeStreamingTransport::new()
    let streaming_resp = transport.request_stream(req) catch {
      @client.TransportError::NetworkError(msg) =>
        raise ValidationFailed(name + ": http transport " + msg)
      @client.TransportError::TimeoutError =>
        raise ValidationFailed(name + ": http transport timeout")
    }
    request_url = transport.last_url
    last_request_body = transport.last_body
    if pending_call_id.length() > 0 {
      carrier_summary =
        "gateway openai->" +
        tool_followup_carrier_summary(
          provider.api,
          last_request_body,
          pending_call_id,
        )
      pending_call_id = ""
    }
    if streaming_resp.status < 200 || streaming_resp.status >= 300 {
      let error_body = read_all_from_stream(streaming_resp.reader) catch { _ => "" }
      let trimmed_message = error_body.trim(chars=" \n\r\t").to_string()
      if is_retryable_model_error(streaming_resp.status, trimmed_message) {
        raise ModelUnavailable(
          model + ": api " + streaming_resp.status.to_string() + " " + trimmed_message,
        )
      } else {
        raise ValidationFailed(
          name + ": api " + streaming_resp.status.to_string() + " " + error_body,
        )
      }
    }
    let seen : Array[String] = []
    let response = translate_streaming_provider_response(
      provider.api,
      model,
      streaming_resp.reader,
      seen,
    )
    for event_type in seen {
      all_events.push(event_type)
    }
    match response {
      @types.ModelResponse::ToolCalls(_)
      | @types.ModelResponse::ToolCallsWithContent(..) => {
        validate_tool_stream_events(seen)
        let extracted = extract_tool_call(response) catch {
          ValidationFailed(message) =>
            raise ValidationFailed(message + "\nrequest=" + last_request_body)
          ModelUnavailable(message) => raise ModelUnavailable(message)
        }
        validate_extracted_tool_call(extracted, label)
        saw_tool_call = true
        messages = append_tool_followup_messages(messages, label, extracted)
        pending_call_id = extracted.call.id
      }
      _ => {
        if not(saw_tool_call) {
          raise ValidationFailed(
            "expected tool call response\nrequest=" + last_request_body,
          )
        }
        let text = extract_response_text(response)
        ignore(validate_tool_json_url_against(text, expected_tool_url(label)))
        return {
          name,
          model,
          mode: "stream",
          request_url,
          carrier_summary,
          event_types: summarize_events(all_events),
          response_text: text.trim(chars=" \n\r\t").to_string(),
        }
      }
    }
  }
  raise ValidationFailed(
    name + ": translated stream tool conversation did not converge" +
      "\nrequest=" + last_request_body,
  )
}

///|
async fn run_openai_surface_tool_translation_stream_check(
  name : String,
  provider : @gateway.ProviderConfig,
  candidates : Array[String],
  label : String,
) -> CheckReport raise LiveCheckError {
  let attempts : Array[String] = []
  for model in candidates {
    let report = attempt_openai_surface_tool_translation_stream_model(
      name,
      provider,
      model,
      label,
    ) catch {
      ModelUnavailable(message) => {
        attempts.push(message)
        continue
      }
      ValidationFailed(message) => raise ValidationFailed(message)
    }
    return report
  }
  let attempted = attempts.join(" | ")
  raise ValidationFailed(
    name + ": no working model candidate. tried=" + attempted,
  )
}

///|
