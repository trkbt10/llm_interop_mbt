async fn attempt_tool_multiturn_sync_model(
  name : String,
  provider : @gateway.ProviderConfig,
  model : String,
  label : String,
) -> CheckReport raise LiveCheckError {
  let first_transport = NativeHttpTransport::new()
  let mut response = @client.chat_gateway_responses(
    provider,
    first_transport,
    tool_turn_one_messages(label),
    [tool_definition()],
    model,
    max_tokens=Some(128),
    temperature=Some(0.0),
  ) catch {
    @client.ClientError::ApiError(code~, message~) => {
      let trimmed_message = message.trim(chars=" \n\r\t").to_string()
      if is_retryable_model_error(code, trimmed_message) {
        raise ModelUnavailable(
          model + ": api " + code.to_string() + " " + trimmed_message,
        )
      } else {
        raise ValidationFailed(name + ": api " + code.to_string() + " " + message)
      }
    }
    @client.ClientError::HttpError(message) =>
      raise ValidationFailed(name + ": http " + message)
    @client.ClientError::ParseError(message) =>
      raise ValidationFailed(name + ": parse " + message)
  }
  let mut messages = tool_turn_one_messages(label)
  let mut last_request_body = first_transport.last_body
  let mut last_response_body = first_transport.last_response_body
  let mut request_url = first_transport.last_url
  let mut carrier_summary = ""
  let mut saw_tool_call = false
  for _ in 0..<4 {
    match response {
      @types.ModelResponse::ToolCalls(_)
      | @types.ModelResponse::ToolCallsWithContent(..) => {
        let extracted = extract_tool_call(response) catch {
          ValidationFailed(message) =>
            raise ValidationFailed(
              message +
                "\nrequest=" + last_request_body +
                "\nresponse=" + last_response_body,
            )
          ModelUnavailable(message) => raise ModelUnavailable(message)
        }
        validate_extracted_tool_call(extracted, label)
        saw_tool_call = true
        messages = append_tool_followup_messages(messages, label, extracted)
        let followup_transport = NativeHttpTransport::new()
        response = @client.chat_gateway_responses(
          provider,
          followup_transport,
          messages,
          [tool_definition()],
          model,
          max_tokens=Some(128),
          temperature=Some(0.0),
          response_format=tool_followup_response_format(provider.api),
        ) catch {
          @client.ClientError::ApiError(code~, message~) =>
            raise ValidationFailed(
              name + ": followup api " + code.to_string() + " " + message,
            )
          @client.ClientError::HttpError(message) =>
            raise ValidationFailed(name + ": followup http " + message)
          @client.ClientError::ParseError(message) =>
            raise ValidationFailed(name + ": followup parse " + message)
        }
        request_url = followup_transport.last_url
        last_request_body = followup_transport.last_body
        last_response_body = followup_transport.last_response_body
        carrier_summary = tool_followup_carrier_summary(
          provider.api,
          last_request_body,
          extracted.call.id,
        )
      }
      _ => {
        if not(saw_tool_call) {
          raise ValidationFailed(
            "expected tool call response\nrequest=" + last_request_body +
              "\nresponse=" + last_response_body,
          )
        }
        let text = extract_response_text(response) catch {
          ValidationFailed(message) =>
            raise ValidationFailed(
              message +
                "\nrequest=" + last_request_body +
                "\nresponse=" + last_response_body,
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
    name + ": tool conversation did not converge" +
      "\nrequest=" + last_request_body +
      "\nresponse=" + last_response_body,
  )
}

///|
async fn run_tool_multiturn_sync_check(
  name : String,
  provider : @gateway.ProviderConfig,
  candidates : Array[String],
  label : String,
) -> CheckReport raise LiveCheckError {
  let attempts : Array[String] = []
  for model in candidates {
    let report = attempt_tool_multiturn_sync_model(
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
async fn attempt_tool_multiturn_stream_model(
  name : String,
  provider : @gateway.ProviderConfig,
  model : String,
  label : String,
) -> CheckReport raise LiveCheckError {
  let stream_transport = NativeStreamingTransport::new()
  let seen : Array[String] = []
  let first_response = @client.chat_gateway_responses_stream(
    provider,
    stream_transport,
    tool_turn_one_messages(label),
    [tool_definition()],
    model,
    on_event=fn(event) { seen.push(event.0) },
    max_tokens=Some(128),
    temperature=Some(0.0),
  ) catch {
    @client.ClientError::ApiError(code~, message~) => {
      let trimmed_message = message.trim(chars=" \n\r\t").to_string()
      if is_retryable_model_error(code, trimmed_message) {
        raise ModelUnavailable(
          model + ": api " + code.to_string() + " " + trimmed_message,
        )
      } else {
        raise ValidationFailed(name + ": api " + code.to_string() + " " + message)
      }
    }
    @client.ClientError::HttpError(message) =>
      raise ValidationFailed(name + ": http " + message)
    @client.ClientError::ParseError(message) =>
      raise ValidationFailed(name + ": parse " + message)
  }
  validate_tool_stream_events(seen)
  let extracted = extract_tool_call(first_response)
  validate_extracted_tool_call(extracted, label)

  let second_transport = NativeHttpTransport::new()
  let final_response = @client.chat_gateway_responses(
    provider,
    second_transport,
    tool_followup_messages(label, extracted),
    [tool_definition()],
    model,
    max_tokens=Some(128),
    temperature=Some(0.0),
    response_format=tool_followup_response_format(provider.api),
  ) catch {
    @client.ClientError::ApiError(code~, message~) =>
      raise ValidationFailed(name + ": followup api " + code.to_string() + " " + message)
    @client.ClientError::HttpError(message) =>
      raise ValidationFailed(name + ": followup http " + message)
    @client.ClientError::ParseError(message) =>
      raise ValidationFailed(name + ": followup parse " + message)
  }
  let text = extract_response_text(final_response)
  ignore(validate_tool_json_url_against(text, expected_tool_url(label)))
  let carrier_summary = tool_followup_carrier_summary(
    provider.api,
    second_transport.last_body,
    extracted.call.id,
  )
  {
    name,
    model,
    mode: "stream",
    request_url: stream_transport.last_url,
    carrier_summary,
    event_types: summarize_events(seen),
    response_text: text.trim(chars=" \n\r\t").to_string(),
  }
}

///|
async fn run_tool_multiturn_stream_check(
  name : String,
  provider : @gateway.ProviderConfig,
  candidates : Array[String],
  label : String,
) -> CheckReport raise LiveCheckError {
  let attempts : Array[String] = []
  for model in candidates {
    let report = attempt_tool_multiturn_stream_model(
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
