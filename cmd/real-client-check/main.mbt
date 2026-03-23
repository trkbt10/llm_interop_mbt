///|
/// Real-provider verification harness for the client package.
///
/// This command uses the public client entry points with a native HTTP transport
/// and sends actual upstream requests. It is intentionally separate from the
/// library test suite because it requires network access and provider API keys.

///|
let request_timeout_ms : Int = 60000

///|
let expected_url : String = "https://example.com/interop-check"

///|
let expected_company : String = "Berkshire Hathaway"

///|
let expected_file_url : String =
  "https://www.berkshirehathaway.com/letters/2024ltr.pdf"

///|
let expected_inline_file_name : String = "company.txt"

///|
let expected_inline_file_text : String = "Berkshire Hathaway"

///|
let expected_inline_file_base64 : String = "QmVya3NoaXJlIEhhdGhhd2F5"

///|
let expected_pdf_file_name : String = "company.pdf"

///|
let expected_pdf_file_content : String =
  "%PDF-1.4\n" +
  "1 0 obj\n" +
  "<< /Type /Catalog /Pages 2 0 R >>\n" +
  "endobj\n" +
  "2 0 obj\n" +
  "<< /Type /Pages /Kids [3 0 R] /Count 1 >>\n" +
  "endobj\n" +
  "3 0 obj\n" +
  "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 144] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>\n" +
  "endobj\n" +
  "4 0 obj\n" +
  "<< /Length 52 >>\n" +
  "stream\n" +
  "BT\n" +
  "/F1 18 Tf\n" +
  "72 96 Td\n" +
  "(Berkshire Hathaway) Tj\n" +
  "ET\n" +
  "endstream\n" +
  "endobj\n" +
  "5 0 obj\n" +
  "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\n" +
  "endobj\n" +
  "xref\n" +
  "0 6\n" +
  "0000000000 65535 f \n" +
  "0000000009 00000 n \n" +
  "0000000058 00000 n \n" +
  "0000000115 00000 n \n" +
  "0000000241 00000 n \n" +
  "0000000343 00000 n \n" +
  "trailer\n" +
  "<< /Root 1 0 R /Size 6 >>\n" +
  "startxref\n" +
  "413\n" +
  "%%EOF\n"

///|
let expected_pdf_file_base64 : String =
  "JVBERi0xLjQKMSAwIG9iago8PCAvVHlwZSAvQ2F0YWxvZyAvUGFnZXMgMiAwIFIgPj4KZW5kb2JqCjIgMCBvYmoKPDwgL1R5cGUgL1BhZ2VzIC9LaWRzIFszIDAgUl0gL0NvdW50IDEgPj4KZW5kb2JqCjMgMCBvYmoKPDwgL1R5cGUgL1BhZ2UgL1BhcmVudCAyIDAgUiAvTWVkaWFCb3ggWzAgMCAzMDAgMTQ0XSAvQ29udGVudHMgNCAwIFIgL1Jlc291cmNlcyA8PCAvRm9udCA8PCAvRjEgNSAwIFIgPj4gPj4gPj4KZW5kb2JqCjQgMCBvYmoKPDwgL0xlbmd0aCA1MiA+PgpzdHJlYW0KQlQKL0YxIDE4IFRmCjcyIDk2IFRkCihCZXJrc2hpcmUgSGF0aGF3YXkpIFRqCkVUCmVuZHN0cmVhbQplbmRvYmoKNSAwIG9iago8PCAvVHlwZSAvRm9udCAvU3VidHlwZSAvVHlwZTEgL0Jhc2VGb250IC9IZWx2ZXRpY2EgPj4KZW5kb2JqCnhyZWYKMCA2CjAwMDAwMDAwMDAgNjU1MzUgZiAKMDAwMDAwMDAwOSAwMDAwMCBuIAowMDAwMDAwMDU4IDAwMDAwIG4gCjAwMDAwMDAxMTUgMDAwMDAgbiAKMDAwMDAwMDI0MSAwMDAwMCBuIAowMDAwMDAwMzQzIDAwMDAwIG4gCnRyYWlsZXIKPDwgL1Jvb3QgMSAwIFIgL1NpemUgNiA+PgpzdGFydHhyZWYKNDEzCiUlRU9GCg=="

///|
fn expected_tool_url(label : String) -> String {
  expected_url + "/" + label
}

///|
suberror LiveCheckError {
  ModelUnavailable(String)
  ValidationFailed(String)
} derive(Show)

///|
struct NativeHttpTransport {
  mut last_url : String
  mut last_body : String
  mut last_response_body : String
}

///|
fn NativeHttpTransport::new() -> NativeHttpTransport {
  { last_url: "", last_body: "", last_response_body: "" }
}

///|
impl @client.HttpTransport for NativeHttpTransport with request(self, req) {
  self.last_url = sanitize_url(req.url)
  self.last_body = req.body.unwrap_or("")
  let body = req.body.unwrap_or("")
  let (response, data) = @async.with_timeout(request_timeout_ms, () => {
    @http.post(req.url, body, headers=req.headers)
  }) catch {
    @async.TimeoutError => raise @client.transport_timeout_error()
    err => raise @client.transport_network_error(err.to_string())
  }
  let text = data.text() catch { _ => "" }
  self.last_response_body = text
  { status: response.code, body: text }
}

///|
struct NativeStreamReader {
  client : @http.Client
  mut closed : Bool
}

///|
fn NativeStreamReader::new(client : @http.Client) -> NativeStreamReader {
  { client, closed: false }
}

///|
impl @client.StreamReader for NativeStreamReader with read(self) {
  if self.closed {
    return None
  }
  let chunk = @async.with_timeout(request_timeout_ms, () => {
    self.client.read_some(max_len=4096)
  }) catch {
    @async.TimeoutError => {
      self.client.close()
      self.closed = true
      raise @client.transport_timeout_error()
    }
    err => {
      self.client.close()
      self.closed = true
      raise @client.transport_network_error(err.to_string())
    }
  }
  match chunk {
    None => {
      self.client.close()
      self.closed = true
      None
    }
    Some(bytes) => Some(bytes)
  }
}

///|
struct NativeStreamingTransport {
  mut last_url : String
  mut last_body : String
}

///|
fn NativeStreamingTransport::new() -> NativeStreamingTransport {
  { last_url: "", last_body: "" }
}

///|
impl @client.StreamingHttpTransport for NativeStreamingTransport with request_stream(
  self,
  req,
) {
  self.last_url = sanitize_url(req.url)
  self.last_body = req.body.unwrap_or("")
  let client = @async.with_timeout(request_timeout_ms, () => {
    @http.post_stream(req.url, headers=req.headers)
  }) catch {
    @async.TimeoutError => raise @client.transport_timeout_error()
    err => raise @client.transport_network_error(err.to_string())
  }
  let body = req.body.unwrap_or("")
  let response = @async.with_timeout(request_timeout_ms, () => {
    if body != "" {
      client.write(body)
      client.flush()
    }
    client.end_request()
  }) catch {
    @async.TimeoutError => {
      client.close()
      raise @client.transport_timeout_error()
    }
    err => {
      client.close()
      raise @client.transport_network_error(err.to_string())
    }
  }
  let reader = NativeStreamReader::new(client)
  { status: response.code, reader }
}

///|
struct ExtractedToolCall {
  call : @types.ToolCallRequest
  assistant_content : String
}

///|
fn env(name : String) -> String {
  @sys.get_env_var(name).unwrap_or("")
}

///|
fn sanitize_url(url : String) -> String {
  guard url.find("key=") is Some(start) else { return url }
  let prefix = url[:start + 4].to_string()
  let rest = url[start + 4:]
  match rest.find("&") {
    Some(end) => prefix + "***" + rest[end:].to_string()
    None => prefix + "***"
  }
}

///|
fn structured_response_format() -> @types.ResponseFormat {
  @types.ResponseFormat::JsonSchema(
    name=Some("interop_check"),
    schema={
      "type": "object",
      "required": ["url"],
      "properties": {
        "url": { "type": "string", "format": "uri" },
      },
    },
    description=Some("Return a single URL object."),
    strict=Some(true),
  )
}

///|
fn json_object_response_format() -> @types.ResponseFormat {
  @types.ResponseFormat::JsonObject
}

///|
fn file_url_response_format() -> @types.ResponseFormat {
  @types.ResponseFormat::JsonSchema(
    name=Some("file_url_check"),
    schema={
      "type": "object",
      "required": ["company"],
      "properties": {
        "company": { "type": "string" },
      },
    },
    description=Some("Return the company name from the attached file."),
    strict=Some(true),
  )
}

///|
fn file_input_prompt() -> String {
  "Read the attached file and return exactly {\"company\":\"\{expected_company}\"}."
}

///|
fn structured_messages() -> Array[@types.ModelMessage] {
  [
    @types.ModelMessage::User(
      content="Return exactly this JSON object and nothing else: {\"url\":\"https://example.com/interop-check\"}",
      name=None,
      content_parts=None,
    ),
  ]
}

///|
fn file_url_messages() -> Array[@types.ModelMessage] {
  let prompt = file_input_prompt()
  [
    @types.ModelMessage::User(
      content=prompt,
      name=None,
      content_parts=Some([
        @types.ContentPart::Text(prompt),
        @types.ContentPart::FileUrl(url=expected_file_url),
      ]),
    ),
  ]
}

///|
fn file_data_messages() -> Array[@types.ModelMessage] {
  let prompt = file_input_prompt()
  [
    @types.ModelMessage::User(
      content=prompt,
      name=None,
      content_parts=Some([
        @types.ContentPart::Text(prompt),
        @types.ContentPart::Document(
          data=expected_inline_file_base64,
          media_type="text/plain",
          title=Some(expected_inline_file_name),
        ),
      ]),
    ),
  ]
}

///|
fn chat_file_data_messages() -> Array[@types.ModelMessage] {
  let prompt = file_input_prompt()
  [
    @types.ModelMessage::User(
      content=prompt,
      name=None,
      content_parts=Some([
        @types.ContentPart::Text(prompt),
        @types.ContentPart::Document(
          data=expected_pdf_file_base64,
          media_type="application/pdf",
          title=Some(expected_pdf_file_name),
        ),
      ]),
    ),
  ]
}

///|
fn file_id_messages(file_id : String) -> Array[@types.ModelMessage] {
  let prompt = file_input_prompt()
  [
    @types.ModelMessage::User(
      content=prompt,
      name=None,
      content_parts=Some([
        @types.ContentPart::Text(prompt),
        @types.ContentPart::FileRef(file_id~, media_type=Some("text/plain")),
      ]),
    ),
  ]
}

///|
fn chat_file_id_messages(file_id : String) -> Array[@types.ModelMessage] {
  let prompt = file_input_prompt()
  [
    @types.ModelMessage::User(
      content=prompt,
      name=None,
      content_parts=Some([
        @types.ContentPart::Text(prompt),
        @types.ContentPart::FileRef(file_id~, media_type=Some("application/pdf")),
      ]),
    ),
  ]
}

///|
fn translation_messages() -> Array[@types.ModelMessage] {
  [
    @types.ModelMessage::System(
      "Return only the requested JSON object with no extra prose.",
    ),
    @types.ModelMessage::User(
      content="Return exactly this JSON object and nothing else: {\"url\":\"https://example.com/interop-check\"}",
      name=None,
      content_parts=None,
    ),
  ]
}

///|
fn raw_openai_surface_translation_body(
  model : String,
  response_format : @types.ResponseFormat,
) -> String {
  @openai.build_chat_body(
    model,
    translation_messages(),
    [],
    max_tokens=Some(128),
    temperature=Some(0.0),
    response_format=Some(response_format),
  ).stringify()
}

///|
fn openai_function_tool_choice(tool_name : String) -> Json {
  {
    "type": "function",
    "function": { "name": tool_name },
  }
}

///|
fn with_json_boolean_field(body : String, key : String) -> String {
  let json = @json.parse(body) catch { _ => return body }
  match json {
    Object(obj) => {
      obj[key] = Json::boolean(true)
      Json::object(obj).stringify()
    }
    _ => body
  }
}

///|
fn raw_openai_surface_tool_body(
  model : String,
  messages : Array[@types.ModelMessage],
  response_format : @types.ResponseFormat?,
  tool_choice : Json?,
) -> String {
  let body = @openai.build_chat_body(
    model,
    messages,
    [tool_definition()],
    max_tokens=Some(128),
    temperature=Some(0.0),
    response_format~,
  )
  match (body, tool_choice) {
    (Object(obj), Some(choice)) => {
      obj["tool_choice"] = choice
      Json::object(obj).stringify()
    }
    _ => body.stringify()
  }
}

///|
fn basic_messages() -> Array[@types.ModelMessage] {
  [
    @types.ModelMessage::User(
      content="Reply with exactly OK and nothing else.",
      name=None,
      content_parts=None,
    ),
  ]
}

///|
fn tool_definition() -> @types.ToolDefinition {
  @types.ToolDefinition::new(
    name="lookup_verification_url",
    description="Return the verification URL for a given label",
    parameters={
      "type": "object",
      "properties": { "label": { "type": "string" } },
      "required": ["label"],
    },
  )
}

///|
fn tool_turn_one_messages(label : String) -> Array[@types.ModelMessage] {
  [
    @types.ModelMessage::User(
      content=
        "Call the tool lookup_verification_url exactly once with {\"label\":\"\{label}\"} and no extra text. After you receive the tool result, reply with exactly that JSON object and nothing else.",
      name=None,
      content_parts=None,
    ),
  ]
}

///|
fn tool_followup_messages(
  label : String,
  extracted : ExtractedToolCall,
) -> Array[@types.ModelMessage] {
  [
    @types.ModelMessage::User(
      content=
        "Call the tool lookup_verification_url exactly once with {\"label\":\"\{label}\"} and no extra text. After you receive the tool result, reply with exactly that JSON object and nothing else.",
      name=None,
      content_parts=None,
    ),
    @types.ModelMessage::Assistant(
      content=extracted.assistant_content,
      tool_calls=Some([extracted.call]),
    ),
    @types.ModelMessage::ToolResult(
      tool_call_id=extracted.call.id,
      content="{\"url\":\"\{expected_tool_url(label)}\"}",
    ),
  ]
}

///|
fn append_tool_followup_messages(
  messages : Array[@types.ModelMessage],
  label : String,
  extracted : ExtractedToolCall,
) -> Array[@types.ModelMessage] {
  let result = messages.copy()
  result.push(
    @types.ModelMessage::Assistant(
      content=extracted.assistant_content,
      tool_calls=Some([extracted.call]),
    ),
  )
  result.push(
    @types.ModelMessage::ToolResult(
      tool_call_id=extracted.call.id,
      content="{\"url\":\"\{expected_tool_url(label)}\"}",
    ),
  )
  result
}

///|
fn provider(
  id : String,
  api : @gateway.ModelApi,
  api_key : String,
  base_url : String,
) -> @gateway.ProviderConfig {
  {
    ..@gateway.ProviderConfig::new(id, api),
    api_key,
    base_url,
  }
}

///|
fn openai_stream_candidates() -> Array[String] {
  let selected_model = env("OPENAI_REALCHECK_MODEL")
  if selected_model != "" {
    [selected_model, "gpt-4.1-mini", "gpt-4.1", "gpt-4o-mini"]
  } else {
    ["gpt-4.1-mini", "gpt-4.1", "gpt-4o-mini"]
  }
}

///|
fn push_unique(values : Array[String], value : String) -> Unit {
  if value != "" && not(values.contains(value)) {
    values.push(value)
  }
}

///|
fn default_anthropic_candidates() -> Array[String] {
  [
    "claude-sonnet-4-6",
    "claude-opus-4-6",
    "claude-opus-4-1-20250805",
    "claude-sonnet-4-5-20250929",
    "claude-haiku-4-5-20251001",
  ]
}

///|
fn append_default_anthropic_candidates(candidates : Array[String]) -> Unit {
  for model in default_anthropic_candidates() {
    push_unique(candidates, model)
  }
}

///|
async fn anthropic_candidates(api_key : String) -> Array[String] {
  let candidates : Array[String] = []
  push_unique(candidates, env("ANTHROPIC_REALCHECK_MODEL"))
  let client = @http.Client::new("https://api.anthropic.com") catch {
    _ => {
      append_default_anthropic_candidates(candidates)
      return candidates
    }
  }
  let response = @async.with_timeout(request_timeout_ms, () => {
    client.get(
      "/v1/models",
      extra_headers={
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
      },
    )
  }) catch {
    _ => {
      client.close()
      append_default_anthropic_candidates(candidates)
      return candidates
    }
  }
  let response_body = @io.Reader::read_all(client) catch {
    _ => {
      client.close()
      append_default_anthropic_candidates(candidates)
      return candidates
    }
  }
  let text = response_body.text() catch { _ => "" }
  client.close()
  if response.code == 200 {
    let json : Json = @json.parse(text) catch {
      _ => {
        append_default_anthropic_candidates(candidates)
        return candidates
      }
    }
    match json {
      { "data": Array(items), .. } =>
        for item in items {
          match item {
            {
              "id": String(id),
              "capabilities": {
                "structured_outputs": { "supported": True, .. },
                ..
              },
              ..
            } => push_unique(candidates, id)
            _ => ()
          }
        }
      _ => ()
    }
  }
  append_default_anthropic_candidates(candidates)
  candidates
}

///|
fn gemini_candidates() -> Array[String] {
  let selected_model = env("GEMINI_REALCHECK_MODEL")
  if selected_model != "" {
    [
      selected_model,
      "gemini-2.0-flash",
      "gemini-2.5-flash-lite",
      "gemini-2.5-flash",
      "gemini-2.0-flash-001",
    ]
  } else {
    [
      "gemini-2.0-flash",
      "gemini-2.5-flash-lite",
      "gemini-2.5-flash",
      "gemini-2.0-flash-001",
    ]
  }
}

///|
fn groq_candidates() -> Array[String] {
  let selected_model = env("GROQ_REALCHECK_MODEL")
  if selected_model != "" {
    [selected_model, "openai/gpt-oss-20b", "llama-3.3-70b-versatile"]
  } else {
    ["openai/gpt-oss-20b", "llama-3.3-70b-versatile"]
  }
}

///|
fn is_retryable_model_error(code : Int, message : String) -> Bool {
  let lower = message.to_lower()
  if code == 429 {
    lower.contains("resource exhausted") ||
    lower.contains("rate limit") ||
    lower.contains("quota") ||
    lower.contains("try again later")
  } else {
    (code == 400 || code == 404 || code == 422) &&
    (
      lower.contains("model") ||
      lower.contains("does not support") ||
      lower.contains("output format") ||
      lower.contains("unsupported") ||
      lower.contains("not found") ||
      lower.contains("does not exist")
    )
  }
}

///|
fn extract_response_text(response : @types.ModelResponse) -> String raise LiveCheckError {
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
    @types.ModelResponse::ModelError(message) =>
      raise ValidationFailed("model error response: " + message)
    @types.ModelResponse::RateLimited(retry_after~) =>
      raise ModelUnavailable("rate limited: retry_after=\{retry_after}")
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
fn validate_openai_responses_carrier(body : String) -> String raise LiveCheckError {
  if not(body.contains("\"text\":{\"format\":")) {
    raise ValidationFailed("OpenAI Responses request missed text.format carrier")
  }
  if body.contains("\"format\":\"uri\"") {
    raise ValidationFailed("OpenAI Responses request leaked uri format")
  }
  if not(body.contains("\"additionalProperties\":false")) {
    raise ValidationFailed(
      "OpenAI Responses request missed strict normalization",
    )
  }
  "responses:text.format normalized(openai)"
}

///|
fn validate_openai_chat_carrier(body : String) -> String raise LiveCheckError {
  if not(body.contains("\"response_format\":{\"type\":\"json_schema\"")) {
    raise ValidationFailed("OpenAI Chat request missed response_format")
  }
  if body.contains("\"format\":\"uri\"") {
    raise ValidationFailed("OpenAI Chat request leaked uri format")
  }
  if not(body.contains("\"additionalProperties\":false")) {
    raise ValidationFailed("OpenAI Chat request missed strict normalization")
  }
  "chat:response_format normalized(openai)"
}

///|
fn validate_openai_responses_json_object_carrier(
  body : String,
) -> String raise LiveCheckError {
  if not(body.contains("\"text\":{\"format\":{\"type\":\"json_object\"")) {
    raise ValidationFailed("OpenAI Responses request missed json_object text.format")
  }
  "responses:text.format json_object"
}

///|
fn validate_openai_chat_json_object_carrier(
  body : String,
) -> String raise LiveCheckError {
  if not(body.contains("\"response_format\":{\"type\":\"json_object\"")) {
    raise ValidationFailed("OpenAI Chat request missed json_object response_format")
  }
  "chat:response_format json_object"
}

///|
fn validate_anthropic_carrier(body : String) -> String raise LiveCheckError {
  if not(body.contains("\"output_config\":{\"format\":{\"type\":\"json_schema\"")) {
    raise ValidationFailed("Anthropic request missed output_config.format carrier")
  }
  if not(body.contains("\"format\":\"uri\"")) {
    raise ValidationFailed("Anthropic request dropped raw uri format")
  }
  if not(body.contains("\"additionalProperties\":false")) {
    raise ValidationFailed(
      "Anthropic request missed required additionalProperties=false normalization",
    )
  }
  "anthropic:output_config.format raw(uri-preserved)+additionalProperties:false"
}

///|
fn validate_anthropic_json_object_carrier(
  body : String,
) -> String raise LiveCheckError {
  if not(body.contains("\"output_config\":{\"format\":{\"type\":\"json_schema\"")) {
    raise ValidationFailed("Anthropic request missed output_config.format carrier")
  }
  if not(body.contains("\"schema\":{\"type\":\"object\"")) {
    raise ValidationFailed("Anthropic json_object request missed object schema")
  }
  if not(body.contains("\"additionalProperties\":false")) {
    raise ValidationFailed(
      "Anthropic json_object request missed additionalProperties=false normalization",
    )
  }
  "anthropic:output_config.format json_object-via-schema"
}

///|
fn validate_gemini_carrier(body : String) -> String raise LiveCheckError {
  if not(body.contains("\"responseMimeType\":\"application/json\"")) {
    raise ValidationFailed("Gemini request missed responseMimeType")
  }
  if not(body.contains("\"responseJsonSchema\"")) {
    raise ValidationFailed("Gemini request missed responseJsonSchema")
  }
  if not(body.contains("\"format\":\"uri\"")) {
    raise ValidationFailed("Gemini request dropped raw uri format")
  }
  if body.contains("\"additionalProperties\":false") {
    raise ValidationFailed("Gemini request unexpectedly normalized schema")
  }
  "gemini:responseJsonSchema raw(uri-preserved)"
}

///|
fn validate_gemini_json_object_carrier(
  body : String,
) -> String raise LiveCheckError {
  if not(body.contains("\"responseMimeType\":\"application/json\"")) {
    raise ValidationFailed("Gemini request missed responseMimeType")
  }
  if body.contains("\"responseJsonSchema\"") || body.contains("\"responseSchema\"") {
    raise ValidationFailed("Gemini json_object request unexpectedly carried schema")
  }
  "gemini:responseMimeType json_object"
}

///|
fn validate_groq_json_object_carrier(body : String) -> String raise LiveCheckError {
  if not(body.contains("\"response_format\":{\"type\":\"json_object\"")) {
    raise ValidationFailed("Groq request missed json_object response_format")
  }
  "groq:chat json_object"
}

///|
fn validate_gateway_openai_to_anthropic_carrier(
  body : String,
) -> String raise LiveCheckError {
  if not(body.contains("\"system\":\"Return only the requested JSON object with no extra prose.\"")) {
    raise ValidationFailed("Anthropic translated request missed system prompt")
  }
  if not(body.contains("\"output_config\":{\"format\":{\"type\":\"json_schema\"")) {
    raise ValidationFailed("Anthropic translated request missed output_config.format carrier")
  }
  if body.contains("\"format\":\"uri\"") {
    raise ValidationFailed("Anthropic translated request leaked raw uri format")
  }
  if not(body.contains("\"additionalProperties\":false")) {
    raise ValidationFailed(
      "Anthropic translated request missed OpenAI strict normalization",
    )
  }
  "gateway openai->anthropic->openai normalized(openai)"
}

///|
fn validate_gateway_openai_to_anthropic_json_object_carrier(
  body : String,
) -> String raise LiveCheckError {
  if not(body.contains("\"system\":\"Return only the requested JSON object with no extra prose.\"")) {
    raise ValidationFailed("Anthropic translated request missed system prompt")
  }
  ignore(validate_anthropic_json_object_carrier(body))
  "gateway openai->anthropic->openai json_object"
}

///|
fn validate_gateway_openai_to_gemini_carrier(
  body : String,
) -> String raise LiveCheckError {
  if not(body.contains("\"systemInstruction\"")) {
    raise ValidationFailed("Gemini translated request missed systemInstruction")
  }
  if not(body.contains("Return only the requested JSON object with no extra prose.")) {
    raise ValidationFailed("Gemini translated request missed system prompt text")
  }
  if not(body.contains("\"responseMimeType\":\"application/json\"")) {
    raise ValidationFailed("Gemini translated request missed responseMimeType")
  }
  if not(body.contains("\"responseJsonSchema\"")) {
    raise ValidationFailed("Gemini translated request missed responseJsonSchema")
  }
  if body.contains("\"format\":\"uri\"") {
    raise ValidationFailed("Gemini translated request leaked raw uri format")
  }
  if not(body.contains("\"additionalProperties\":false")) {
    raise ValidationFailed(
      "Gemini translated request missed OpenAI strict normalization",
    )
  }
  "gateway openai->gemini->openai normalized(openai)"
}

///|
fn validate_gateway_openai_to_gemini_json_object_carrier(
  body : String,
) -> String raise LiveCheckError {
  if not(body.contains("\"systemInstruction\"")) {
    raise ValidationFailed("Gemini translated request missed systemInstruction")
  }
  if not(body.contains("Return only the requested JSON object with no extra prose.")) {
    raise ValidationFailed("Gemini translated request missed system prompt text")
  }
  ignore(validate_gemini_json_object_carrier(body))
  "gateway openai->gemini->openai json_object"
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
fn validate_file_url_company_response(text : String) -> Unit raise LiveCheckError {
  validate_company_response(text)
}

///|
fn validate_basic_carrier(body : String) -> String raise LiveCheckError {
  if body == "__never__" {
    raise ValidationFailed("unreachable basic carrier sentinel")
  }
  "groq:chat basic"
}

///|
fn validate_openai_responses_file_url_carrier(
  body : String,
) -> String raise LiveCheckError {
  ignore(validate_openai_responses_carrier(body))
  if not(body.contains("\"type\":\"input_file\"")) {
    raise ValidationFailed("OpenAI Responses request missed input_file part")
  }
  if not(body.contains("\"file_url\":\"\{expected_file_url}\"")) {
    raise ValidationFailed("OpenAI Responses request missed file_url carrier")
  }
  "responses:input_file.file_url + text.format normalized(openai)"
}

///|
fn validate_openai_responses_file_data_carrier(
  body : String,
) -> String raise LiveCheckError {
  ignore(validate_openai_responses_carrier(body))
  if not(body.contains("\"type\":\"input_file\"")) {
    raise ValidationFailed("OpenAI Responses request missed input_file part")
  }
  if not(
    body.contains(
      "\"file_data\":\"data:text/plain;base64,\{expected_inline_file_base64}\"",
    )
  ) {
    raise ValidationFailed("OpenAI Responses request missed file_data carrier")
  }
  if not(body.contains("\"filename\":\"\{expected_inline_file_name}\"")) {
    raise ValidationFailed("OpenAI Responses request missed input filename")
  }
  "responses:input_file.file_data + text.format normalized(openai)"
}

///|
fn validate_openai_responses_file_id_carrier(
  body : String,
  file_id : String,
) -> String raise LiveCheckError {
  ignore(validate_openai_responses_carrier(body))
  if not(body.contains("\"type\":\"input_file\"")) {
    raise ValidationFailed("OpenAI Responses request missed input_file part")
  }
  if not(body.contains("\"file_id\":\"\{file_id}\"")) {
    raise ValidationFailed("OpenAI Responses request missed file_id carrier")
  }
  "responses:input_file.file_id + text.format normalized(openai)"
}

///|
fn validate_openai_chat_file_data_carrier(
  body : String,
) -> String raise LiveCheckError {
  if not(body.contains("\"response_format\":{\"type\":\"json_schema\"")) {
    raise ValidationFailed("OpenAI Chat request missed response_format")
  }
  if not(body.contains("\"type\":\"file\"")) {
    raise ValidationFailed("OpenAI Chat request missed file content part")
  }
  if not(
    body.contains(
      "\"file_data\":\"data:application/pdf;base64,\{expected_pdf_file_base64}\"",
    )
  ) {
    raise ValidationFailed("OpenAI Chat request missed file_data carrier")
  }
  if not(body.contains("\"filename\":\"\{expected_pdf_file_name}\"")) {
    raise ValidationFailed("OpenAI Chat request missed file filename")
  }
  "chat:file.file_data + response_format normalized(openai)"
}

///|
fn validate_openai_chat_file_id_carrier(
  body : String,
  file_id : String,
) -> String raise LiveCheckError {
  if not(body.contains("\"response_format\":{\"type\":\"json_schema\"")) {
    raise ValidationFailed("OpenAI Chat request missed response_format")
  }
  if not(body.contains("\"type\":\"file\"")) {
    raise ValidationFailed("OpenAI Chat request missed file content part")
  }
  if not(body.contains("\"file_id\":\"\{file_id}\"")) {
    raise ValidationFailed("OpenAI Chat request missed file_id carrier")
  }
  "chat:file.file_id + response_format normalized(openai)"
}

///|
fn build_openai_file_upload_body(
  boundary : String,
  filename : String,
  mime_type : String,
  content : String,
) -> String {
  "--\{boundary}\r\n" +
  "Content-Disposition: form-data; name=\"purpose\"\r\n\r\n" +
  "user_data\r\n" +
  "--\{boundary}\r\n" +
  "Content-Disposition: form-data; name=\"file\"; filename=\"\{filename}\"\r\n" +
  "Content-Type: \{mime_type}\r\n\r\n" +
  content +
  "\r\n--\{boundary}--\r\n"
}

///|
async fn upload_openai_text_file(api_key : String) -> String raise LiveCheckError {
  let boundary = "llm_interop_realcheck_upload_boundary"
  let body = build_openai_file_upload_body(
    boundary,
    expected_inline_file_name,
    "text/plain",
    expected_inline_file_text,
  )
  let headers = {
    "Authorization": "Bearer " + api_key,
    "Content-Type": "multipart/form-data; boundary=" + boundary,
  }
  let (response, data) = @async.with_timeout(request_timeout_ms, () => {
    @http.post("https://api.openai.com/v1/files", body, headers=headers)
  }) catch {
    @async.TimeoutError =>
      raise ValidationFailed("openai file upload timed out")
    err =>
      raise ValidationFailed("openai file upload transport error: " + err.to_string())
  }
  let text = data.text() catch { _ => "" }
  if response.code < 200 || response.code >= 300 {
    raise ValidationFailed(
      "openai file upload failed: " + response.code.to_string() + " " + text,
    )
  }
  let json = @json.parse(text) catch {
    err =>
      raise ValidationFailed(
        "openai file upload returned invalid JSON: " + err.to_string(),
      )
  }
  match json {
    { "id": String(file_id), .. } => file_id
    _ => raise ValidationFailed("openai file upload response missed file id")
  }
}

///|
async fn upload_openai_pdf_file(api_key : String) -> String raise LiveCheckError {
  let boundary = "llm_interop_realcheck_upload_boundary_pdf"
  let body = build_openai_file_upload_body(
    boundary,
    expected_pdf_file_name,
    "application/pdf",
    expected_pdf_file_content,
  )
  let headers = {
    "Authorization": "Bearer " + api_key,
    "Content-Type": "multipart/form-data; boundary=" + boundary,
  }
  let (response, data) = @async.with_timeout(request_timeout_ms, () => {
    @http.post("https://api.openai.com/v1/files", body, headers=headers)
  }) catch {
    @async.TimeoutError =>
      raise ValidationFailed("openai pdf upload timed out")
    err =>
      raise ValidationFailed("openai pdf upload transport error: " + err.to_string())
  }
  let text = data.text() catch { _ => "" }
  if response.code < 200 || response.code >= 300 {
    raise ValidationFailed(
      "openai pdf upload failed: " + response.code.to_string() + " " + text,
    )
  }
  let json = @json.parse(text) catch {
    err =>
      raise ValidationFailed(
        "openai pdf upload returned invalid JSON: " + err.to_string(),
      )
  }
  match json {
    { "id": String(file_id), .. } => file_id
    _ => raise ValidationFailed("openai pdf upload response missed file id")
  }
}

///|
fn extract_tool_call(
  response : @types.ModelResponse,
) -> ExtractedToolCall raise LiveCheckError {
  match response {
    @types.ModelResponse::ToolCalls(calls) =>
      if calls.length() > 0 {
        { call: calls[0], assistant_content: "" }
      } else {
        raise ValidationFailed("expected at least one tool call")
      }
    @types.ModelResponse::ToolCallsWithContent(tool_calls~, rich~) =>
      if tool_calls.length() > 0 {
        { call: tool_calls[0], assistant_content: rich.content }
      } else {
        raise ValidationFailed("expected at least one tool call")
      }
    @types.ModelResponse::RateLimited(retry_after~) =>
      raise ModelUnavailable("rate limited: retry_after=\{retry_after}")
    _ => raise ValidationFailed("expected tool call response")
  }
}

///|
fn validate_extracted_tool_call(
  extracted : ExtractedToolCall,
  label : String,
) -> Unit raise LiveCheckError {
  if extracted.call.id.length() == 0 {
    raise ValidationFailed("tool call id was empty")
  }
  if extracted.call.name != "lookup_verification_url" {
    raise ValidationFailed("unexpected tool name: " + extracted.call.name)
  }
  if not(extracted.call.arguments.stringify().contains(label)) {
    raise ValidationFailed(
      "tool call arguments did not preserve expected label: " +
        extracted.call.arguments.stringify(),
    )
  }
}

///|
fn tool_followup_carrier_summary(
  api : @gateway.ModelApi,
  body : String,
  call_id : String,
) -> String raise LiveCheckError {
  match api {
    @gateway.OpenAIResponses => {
      if not(body.contains("\"function_call_output\"")) {
        raise ValidationFailed("OpenAI followup request missed function_call_output")
      }
      if not(body.contains("\"call_id\":\"\{call_id}\"")) {
        raise ValidationFailed("OpenAI followup request missed original call_id")
      }
      "toolcall followup openai call_id preserved"
    }
    @gateway.AnthropicMessages => {
      if not(body.contains("\"tool_result\"")) {
        raise ValidationFailed("Anthropic followup request missed tool_result block")
      }
      let expected_native_id = @interop_util.convert_tool_call_id_to(
        call_id,
        @interop_util.ToolCallIdProvider::AnthropicClaude,
      )
      let has_raw_id = body.contains("\"tool_use_id\":\"\{call_id}\"")
      let has_native_id = body.contains("\"tool_use_id\":\"\{expected_native_id}\"")
      if not(has_raw_id || has_native_id) {
        raise ValidationFailed(
          "Anthropic followup request missed consistent tool_use_id expected_raw=\{call_id} expected_native=\{expected_native_id} body=\{body}",
        )
      }
      "toolcall followup anthropic tool_use_id mapped"
    }
    @gateway.GoogleGenerativeAI => {
      if not(body.contains("\"functionResponse\"")) {
        raise ValidationFailed("Gemini followup request missed functionResponse")
      }
      if not(body.contains("\"lookup_verification_url\"")) {
        raise ValidationFailed("Gemini followup request missed functionResponse name")
      }
      "toolcall followup gemini functionResponse mapped"
    }
    _ => "toolcall followup"
  }
}

///|
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

///|
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
async fn run_openai_checks(
  opts : CliOptions,
  declared : Array[String],
  reports : Array[CheckReport],
  failures : Array[String],
) -> Unit {
  let check_names = [
    "openai.responses.stream.structured",
    "openai.responses.sync.structured",
    "openai.chat.sync.structured",
    "openai.responses.sync.json_object",
    "openai.responses.stream.json_object",
    "openai.chat.sync.json_object",
    "openai.responses.sync.file_url",
    "openai.responses.stream.file_url",
    "openai.responses.sync.file_data",
    "openai.responses.stream.file_data",
    "openai.chat.sync.file_data",
    "openai.responses.sync.file_id",
    "openai.responses.stream.file_id",
    "openai.chat.sync.file_id",
    "openai.responses.sync.toolcall.multiturn",
    "openai.responses.stream.toolcall.multiturn",
  ]
  register_checks(declared, check_names)
  if opts.list || not(any_selected_check(opts, check_names)) {
    return
  }
  let api_key = env("OPENAI_API_KEY")
  if api_key == "" {
    print_skip("openai", "OPENAI_API_KEY is not exported")
    return
  }
  let responses_provider = provider(
    "openai",
    @gateway.OpenAIResponses,
    api_key,
    "https://api.openai.com/v1",
  )
  let chat_provider = provider(
    "openai",
    @gateway.OpenAICompletions,
    api_key,
    "https://api.openai.com/v1",
  )
  let mut uploaded_text_file_id : String? = None
  let mut uploaded_pdf_file_id : String? = None
  if should_run_check(opts, "openai.responses.stream.structured") {
    let stream_report = Some(
      run_stream_check(
        "openai.responses.stream.structured",
        responses_provider,
        openai_stream_candidates(),
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
    match stream_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "openai.responses.sync.structured") {
    let responses_sync_report = Some(
      run_responses_sync_check(
        "openai.responses.sync.structured",
        responses_provider,
        openai_stream_candidates(),
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
    match responses_sync_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "openai.chat.sync.structured") {
    let chat_report = Some(
      run_chat_check(
        "openai.chat.sync.structured",
        chat_provider,
        openai_stream_candidates(),
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
    match chat_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "openai.responses.sync.json_object") {
    let responses_json_object_sync_report = Some(
      run_responses_sync_check(
        "openai.responses.sync.json_object",
        responses_provider,
        openai_stream_candidates(),
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
    match responses_json_object_sync_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "openai.responses.stream.json_object") {
    let responses_json_object_stream_report = Some(
      run_stream_check(
        "openai.responses.stream.json_object",
        responses_provider,
        openai_stream_candidates(),
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
    match responses_json_object_stream_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "openai.chat.sync.json_object") {
    let chat_json_object_report = Some(
      run_chat_check(
        "openai.chat.sync.json_object",
        chat_provider,
        openai_stream_candidates(),
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
    match chat_json_object_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "openai.responses.sync.file_url") {
    let responses_file_url_sync_report = Some(
      run_responses_sync_check_with_messages(
        "openai.responses.sync.file_url",
        responses_provider,
        openai_stream_candidates(),
        file_url_response_format(),
        file_url_messages(),
        validate_file_url_company_response,
        validate_openai_responses_file_url_carrier,
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("openai.responses.sync.file_url", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("openai.responses.sync.file_url", message)
        None
      }
    }
    match responses_file_url_sync_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "openai.responses.stream.file_url") {
    let responses_file_url_stream_report = Some(
      run_stream_check_with_messages(
        "openai.responses.stream.file_url",
        responses_provider,
        openai_stream_candidates(),
        file_url_response_format(),
        file_url_messages(),
        validate_file_url_company_response,
        validate_openai_responses_file_url_carrier,
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("openai.responses.stream.file_url", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("openai.responses.stream.file_url", message)
        None
      }
    }
    match responses_file_url_stream_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "openai.responses.sync.file_data") {
    let responses_file_data_sync_report = Some(
      run_responses_sync_check_with_messages(
        "openai.responses.sync.file_data",
        responses_provider,
        openai_stream_candidates(),
        file_url_response_format(),
        file_data_messages(),
        validate_company_response,
        validate_openai_responses_file_data_carrier,
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("openai.responses.sync.file_data", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("openai.responses.sync.file_data", message)
        None
      }
    }
    match responses_file_data_sync_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "openai.responses.stream.file_data") {
    let responses_file_data_stream_report = Some(
      run_stream_check_with_messages(
        "openai.responses.stream.file_data",
        responses_provider,
        openai_stream_candidates(),
        file_url_response_format(),
        file_data_messages(),
        validate_company_response,
        validate_openai_responses_file_data_carrier,
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("openai.responses.stream.file_data", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("openai.responses.stream.file_data", message)
        None
      }
    }
    match responses_file_data_stream_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "openai.chat.sync.file_data") {
    let chat_file_data_report = Some(
      run_chat_check(
        "openai.chat.sync.file_data",
        chat_provider,
        openai_stream_candidates(),
        Some(file_url_response_format()),
        chat_file_data_messages(),
        validate_company_response,
        validate_openai_chat_file_data_carrier,
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("openai.chat.sync.file_data", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("openai.chat.sync.file_data", message)
        None
      }
    }
    match chat_file_data_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "openai.responses.sync.file_id") {
    let responses_file_id_sync_report = Some({
      let file_id = match uploaded_text_file_id {
        Some(id) => id
        None => {
          let id = upload_openai_text_file(api_key)
          uploaded_text_file_id = Some(id)
          id
        }
      }
      run_responses_sync_check_with_messages(
        "openai.responses.sync.file_id",
        responses_provider,
        openai_stream_candidates(),
        file_url_response_format(),
        file_id_messages(file_id),
        validate_company_response,
        (body) => validate_openai_responses_file_id_carrier(body, file_id),
      )
    }) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("openai.responses.sync.file_id", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("openai.responses.sync.file_id", message)
        None
      }
    }
    match responses_file_id_sync_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "openai.responses.stream.file_id") {
    let responses_file_id_stream_report = Some({
      let file_id = match uploaded_text_file_id {
        Some(id) => id
        None => {
          let id = upload_openai_text_file(api_key)
          uploaded_text_file_id = Some(id)
          id
        }
      }
      run_stream_check_with_messages(
        "openai.responses.stream.file_id",
        responses_provider,
        openai_stream_candidates(),
        file_url_response_format(),
        file_id_messages(file_id),
        validate_company_response,
        (body) => validate_openai_responses_file_id_carrier(body, file_id),
      )
    }) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("openai.responses.stream.file_id", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("openai.responses.stream.file_id", message)
        None
      }
    }
    match responses_file_id_stream_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "openai.chat.sync.file_id") {
    let chat_file_id_report = Some({
      let file_id = match uploaded_pdf_file_id {
        Some(id) => id
        None => {
          let id = upload_openai_pdf_file(api_key)
          uploaded_pdf_file_id = Some(id)
          id
        }
      }
      run_chat_check(
        "openai.chat.sync.file_id",
        chat_provider,
        openai_stream_candidates(),
        Some(file_url_response_format()),
        chat_file_id_messages(file_id),
        validate_company_response,
        (body) => validate_openai_chat_file_id_carrier(body, file_id),
      )
    }) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("openai.chat.sync.file_id", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("openai.chat.sync.file_id", message)
        None
      }
    }
    match chat_file_id_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "openai.responses.sync.toolcall.multiturn") {
    let tool_sync_report = Some(
      run_tool_multiturn_sync_check(
        "openai.responses.sync.toolcall.multiturn",
        responses_provider,
        openai_stream_candidates(),
        "openai-sync",
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("openai.responses.sync.toolcall.multiturn", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("openai.responses.sync.toolcall.multiturn", message)
        None
      }
    }
    match tool_sync_report {
      Some(report) => record_check_success(opts, reports, report)
      None => ()
    }
  }
  if should_run_check(opts, "openai.responses.stream.toolcall.multiturn") {
    let tool_stream_report = Some(
      run_tool_multiturn_stream_check(
        "openai.responses.stream.toolcall.multiturn",
        responses_provider,
        openai_stream_candidates(),
        "openai-stream",
      ),
    ) catch {
      ValidationFailed(message) => {
        failures.push(message)
        print_failure("openai.responses.stream.toolcall.multiturn", message)
        None
      }
      ModelUnavailable(message) => {
        failures.push(message)
        print_failure("openai.responses.stream.toolcall.multiturn", message)
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
      print_failure("groq.chat.sync.json_object", message)
      if not(opts.filters.length() == 0 || wants_basic) {
        failures.push(message)
        return
      }
      let fallback = run_chat_check(
        "groq.chat.sync.basic",
        provider,
        groq_candidates(),
        None,
        basic_messages(),
        validate_exact_ok,
        validate_basic_carrier,
      ) catch {
        ValidationFailed(fallback_message) => {
          failures.push(message + " | fallback: " + fallback_message)
          print_failure("groq.chat.sync.basic", fallback_message)
          return
        }
        ModelUnavailable(fallback_message) => {
          failures.push(message + " | fallback: " + fallback_message)
          print_failure("groq.chat.sync.basic", fallback_message)
          return
        }
      }
      record_check_success(opts, reports, fallback)
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
async fn main {
  let opts = parse_real_client_check_args(@sys.get_cli_args())
  if opts.help {
    print_real_client_check_help()
    return
  }
  let declared : Array[String] = []
  let reports : Array[CheckReport] = []
  let failures : Array[String] = []
  if not(opts.list) {
    println("real client check starting")
  }
  run_openai_checks(opts, declared, reports, failures)
  run_anthropic_check(opts, declared, reports, failures)
  run_gemini_check(opts, declared, reports, failures)
  run_groq_check(opts, declared, reports, failures)
  if opts.list {
    print_available_checks(declared)
    return
  }
  if selected_check_count(opts, declared) == 0 {
    print_failure("real-client-check", "no checks matched the current filter")
    @sys.exit(1)
  }
  println(
    "real client check finished: ok=\{reports.length()} fail=\{failures.length()}",
  )
  if failures.length() > 0 {
    @sys.exit(1)
  }
}
