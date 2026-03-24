async fn attempt_stream_model_with_messages(
  name : String,
  provider : @gateway.ProviderConfig,
  model : String,
  response_format : @types.ResponseFormat,
  messages : Array[@types.ModelMessage],
  validator : (String) -> Unit raise LiveCheckError,
  carrier_check : (String) -> String raise LiveCheckError,
) -> CheckReport raise LiveCheckError {
  let transport = NativeStreamingTransport::new()
  let seen : Array[String] = []
  let response = @client.chat_gateway_responses_stream(
    provider,
    transport,
    messages,
    [],
    model,
    on_event=fn(event) { seen.push(event.0) },
    max_tokens=Some(128),
    temperature=Some(0.0),
    response_format=Some(response_format),
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
  let text = extract_response_text(response)
  validator(text)
  validate_stream_events(seen)
  let carrier_summary = carrier_check(transport.last_body)
  {
    name,
    model,
    mode: "stream",
    request_url: transport.last_url,
    carrier_summary,
    event_types: summarize_events(seen),
    response_text: text.trim(chars=" \n\r\t").to_string(),
  }
}

///|
async fn run_stream_check(
  name : String,
  provider : @gateway.ProviderConfig,
  candidates : Array[String],
  response_format : @types.ResponseFormat,
  validator : (String) -> Unit raise LiveCheckError,
  carrier_check : (String) -> String raise LiveCheckError,
) -> CheckReport raise LiveCheckError {
  run_stream_check_with_messages(
    name,
    provider,
    candidates,
    response_format,
    structured_messages(),
    validator,
    carrier_check,
  )
}

///|
async fn run_stream_check_with_messages(
  name : String,
  provider : @gateway.ProviderConfig,
  candidates : Array[String],
  response_format : @types.ResponseFormat,
  messages : Array[@types.ModelMessage],
  validator : (String) -> Unit raise LiveCheckError,
  carrier_check : (String) -> String raise LiveCheckError,
) -> CheckReport raise LiveCheckError {
  let attempts : Array[String] = []
  for model in candidates {
    let report = attempt_stream_model_with_messages(
      name,
      provider,
      model,
      response_format,
      messages,
      validator,
      carrier_check,
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
async fn attempt_responses_sync_model_with_messages(
  name : String,
  provider : @gateway.ProviderConfig,
  model : String,
  response_format : @types.ResponseFormat,
  messages : Array[@types.ModelMessage],
  validator : (String) -> Unit raise LiveCheckError,
  carrier_check : (String) -> String raise LiveCheckError,
) -> CheckReport raise LiveCheckError {
  let transport = NativeHttpTransport::new()
  let response = @client.chat_gateway_responses(
    provider,
    transport,
    messages,
    [],
    model,
    max_tokens=Some(128),
    temperature=Some(0.0),
    response_format=Some(response_format),
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
  let text = extract_response_text(response)
  validator(text)
  let carrier_summary = carrier_check(transport.last_body)
  {
    name,
    model,
    mode: "sync",
    request_url: transport.last_url,
    carrier_summary,
    event_types: [],
    response_text: text.trim(chars=" \n\r\t").to_string(),
  }
}

///|
async fn run_responses_sync_check(
  name : String,
  provider : @gateway.ProviderConfig,
  candidates : Array[String],
  response_format : @types.ResponseFormat,
  validator : (String) -> Unit raise LiveCheckError,
  carrier_check : (String) -> String raise LiveCheckError,
) -> CheckReport raise LiveCheckError {
  run_responses_sync_check_with_messages(
    name,
    provider,
    candidates,
    response_format,
    structured_messages(),
    validator,
    carrier_check,
  )
}

///|
async fn run_responses_sync_check_with_messages(
  name : String,
  provider : @gateway.ProviderConfig,
  candidates : Array[String],
  response_format : @types.ResponseFormat,
  messages : Array[@types.ModelMessage],
  validator : (String) -> Unit raise LiveCheckError,
  carrier_check : (String) -> String raise LiveCheckError,
) -> CheckReport raise LiveCheckError {
  let attempts : Array[String] = []
  for model in candidates {
    let report = attempt_responses_sync_model_with_messages(
      name,
      provider,
      model,
      response_format,
      messages,
      validator,
      carrier_check,
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
async fn attempt_chat_model(
  name : String,
  provider : @gateway.ProviderConfig,
  model : String,
  response_format : @types.ResponseFormat?,
  messages : Array[@types.ModelMessage],
  validator : (String) -> Unit raise LiveCheckError,
  carrier_check : (String) -> String raise LiveCheckError,
) -> CheckReport raise LiveCheckError {
  let transport = NativeHttpTransport::new()
  let response = @client.chat_gateway(
    provider,
    transport,
    messages,
    [],
    model,
    max_tokens=Some(128),
    temperature=Some(0.0),
    response_format~,
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
  let text = extract_response_text(response)
  validator(text)
  let carrier_summary = carrier_check(transport.last_body)
  {
    name,
    model,
    mode: "sync",
    request_url: transport.last_url,
    carrier_summary,
    event_types: [],
    response_text: text.trim(chars=" \n\r\t").to_string(),
  }
}

///|
async fn run_chat_check(
  name : String,
  provider : @gateway.ProviderConfig,
  candidates : Array[String],
  response_format : @types.ResponseFormat?,
  messages : Array[@types.ModelMessage],
  validator : (String) -> Unit raise LiveCheckError,
  carrier_check : (String) -> String raise LiveCheckError,
) -> CheckReport raise LiveCheckError {
  let attempts : Array[String] = []
  for model in candidates {
    let report = attempt_chat_model(
      name,
      provider,
      model,
      response_format,
      messages,
      validator,
      carrier_check,
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
