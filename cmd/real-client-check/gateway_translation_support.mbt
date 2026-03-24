fn build_gateway_transport_request(
  upstream : @gateway.UpstreamRequest,
) -> @client.TransportRequest {
  {
    url: upstream.origin + upstream.path,
    http_method: "POST",
    headers: upstream.headers,
    body: Some(upstream.body),
  }
}

///|
fn build_openai_surface_stream_request(
  provider : @gateway.ProviderConfig,
  source_body : String,
  model : String,
) -> @client.TransportRequest {
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
  let backend_model = match provider.model_aliases.get(model) {
    Some(mapped) => mapped
    None => model
  }
  let url = match provider.api {
    @gateway.GoogleGenerativeAI => {
      let (_origin, base_path) = @utils.parse_url(base_url)
      upstream.origin +
      @gemini.stream_completion_path(base_path, backend_model, provider.api_key)
    }
    _ => upstream.origin + upstream.path
  }
  let body = match provider.api {
    @gateway.GoogleGenerativeAI => upstream.body
    _ => with_json_boolean_field(upstream.body, "stream")
  }
  {
    url,
    http_method: "POST",
    headers: upstream.headers,
    body: Some(body),
  }
}

///|
fn bytes_to_string_lossy(bytes : Bytes) -> String {
  @utf8.decode(bytes[:]) catch { _ => "" }
}

///|
async fn read_all_from_stream(reader : &@client.StreamReader) -> String {
  let buf = StringBuilder::new()
  while true {
    let chunk = reader.read() catch { _ => break }
    match chunk {
      None => break
      Some(bytes) => buf.write_string(bytes_to_string_lossy(bytes))
    }
  }
  buf.to_string()
}

///|
async fn translate_streaming_provider_response(
  api : @gateway.ModelApi,
  model : String,
  reader : &@client.StreamReader,
  seen : Array[String],
) -> @types.ModelResponse raise LiveCheckError {
  let translator = @gateway.create_responses_api_translator(
    api,
    response_id=@gateway.fallback_response_id(model),
    model=model,
  )
  let acc = @openai.ResponsesApiAccumulator::new()
  let mut sse_buffer = ""
  while true {
    let chunk = reader.read() catch {
      @client.TransportError::NetworkError(msg) =>
        raise ValidationFailed("stream read error: " + msg)
      @client.TransportError::TimeoutError =>
        raise ValidationFailed("stream read timeout")
    }
    match chunk {
      None => break
      Some(bytes) => {
        let parsed = @sse.parse_sse_chunk(sse_buffer + bytes_to_string_lossy(bytes))
        for event in parsed.events {
          let translated = translator.translate(event)
          for pair in translated {
            let (event_type, event_data) = pair
            seen.push(event_type)
            acc.feed({ event: event_type, data: event_data })
          }
        }
        sse_buffer = parsed.remaining
      }
    }
  }
  acc.finish()
}

///|
fn parse_translated_openai_response_text(
  body : String,
) -> String raise LiveCheckError {
  let response = parse_translated_openai_response(body)
  extract_response_text(response)
}

///|
fn parse_translated_openai_response(
  body : String,
) -> @types.ModelResponse raise LiveCheckError {
  let json : Json = @json.parse(body) catch {
    _ =>
      raise ValidationFailed(
        "translated OpenAI response was not valid JSON: " + body,
      )
  }
  @openai.parse_chat_response(json)
}

///|
