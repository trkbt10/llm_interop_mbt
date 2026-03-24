async fn attempt_openai_surface_translation_model(
  name : String,
  provider : @gateway.ProviderConfig,
  model : String,
  response_format : @types.ResponseFormat,
  validator : (String) -> Unit raise LiveCheckError,
  carrier_check : (String) -> String raise LiveCheckError,
) -> CheckReport raise LiveCheckError {
  let source_body = raw_openai_surface_translation_body(model, response_format)
  let base_url = if provider.base_url.is_empty() {
    provider.api.default_base_url()
  } else {
    provider.base_url
  }
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
  let text = parse_translated_openai_response_text(translated)
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
async fn run_openai_surface_translation_check(
  name : String,
  provider : @gateway.ProviderConfig,
  candidates : Array[String],
  response_format : @types.ResponseFormat,
  validator : (String) -> Unit raise LiveCheckError,
  carrier_check : (String) -> String raise LiveCheckError,
) -> CheckReport raise LiveCheckError {
  let attempts : Array[String] = []
  for model in candidates {
    let report = attempt_openai_surface_translation_model(
      name,
      provider,
      model,
      response_format,
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
async fn attempt_openai_surface_stream_translation_model(
  name : String,
  provider : @gateway.ProviderConfig,
  model : String,
  response_format : @types.ResponseFormat,
  validator : (String) -> Unit raise LiveCheckError,
  carrier_check : (String) -> String raise LiveCheckError,
) -> CheckReport raise LiveCheckError {
  let transport = NativeStreamingTransport::new()
  let req = build_openai_surface_stream_request(
    provider,
    raw_openai_surface_translation_body(model, response_format),
    model,
  )
  let streaming_resp = transport.request_stream(req) catch {
    @client.TransportError::NetworkError(msg) =>
      raise ValidationFailed(name + ": http transport " + msg)
    @client.TransportError::TimeoutError =>
      raise ValidationFailed(name + ": http transport timeout")
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
async fn run_openai_surface_stream_translation_check(
  name : String,
  provider : @gateway.ProviderConfig,
  candidates : Array[String],
  response_format : @types.ResponseFormat,
  validator : (String) -> Unit raise LiveCheckError,
  carrier_check : (String) -> String raise LiveCheckError,
) -> CheckReport raise LiveCheckError {
  let attempts : Array[String] = []
  for model in candidates {
    let report = attempt_openai_surface_stream_translation_model(
      name,
      provider,
      model,
      response_format,
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
