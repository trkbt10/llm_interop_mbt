///|
/// Constructors and helpers

///|
/// Create default ToolCallRequest
pub fn ToolCallRequest::default() -> ToolCallRequest {
  { id: "", name: "", arguments: Json::null(), kind: ToolCallKind::Function }
}

///|
/// Create new ToolCallRequest
pub fn ToolCallRequest::new(
  id~ : String,
  name~ : String,
  arguments~ : Json,
) -> ToolCallRequest {
  { id, name, arguments, kind: ToolCallKind::Function }
}

///|
/// Create web search ToolCallRequest
pub fn ToolCallRequest::web_search(
  id~ : String,
  query? : String? = None,
  queries? : Array[String]? = None,
) -> ToolCallRequest {
  let arguments : Map[String, Json] = {}
  match query {
    Some(q) => arguments["query"] = Json::string(q)
    None => ()
  }
  match queries {
    Some(qs) =>
      arguments["queries"] = Json::array(qs.map(fn(q) { Json::string(q) }))
    None => ()
  }
  {
    id,
    name: web_search_tool_name(),
    arguments: Json::object(arguments),
    kind: ToolCallKind::WebSearch,
  }
}

///|
/// Create generic builtin ToolCallRequest
pub fn ToolCallRequest::builtin(
  id~ : String,
  type_~ : String,
  payload? : Json = Json::object({}),
  name? : String = "",
) -> ToolCallRequest {
  let resolved_name = if name.length() > 0 { name } else { type_ }
  {
    id,
    name: resolved_name,
    arguments: payload,
    kind: ToolCallKind::Builtin(builtin_type=type_),
  }
}

///|
/// Create URL citation annotation
pub fn ResponseAnnotation::url_citation(
  url~ : String,
  start_index~ : Int,
  end_index~ : Int,
  title? : String? = None,
) -> ResponseAnnotation {
  UrlCitation(title~, url~, start_index~, end_index~)
}

///|
/// Create document char citation annotation
pub fn ResponseAnnotation::document_char_citation(
  cited_text~ : String,
  document_index~ : Int,
  document_title~ : String,
  file_id~ : String,
  start_char_index~ : Int,
  end_char_index~ : Int,
  start_index~ : Int,
  end_index~ : Int,
) -> ResponseAnnotation {
  DocumentCharCitation(
    cited_text~,
    document_index~,
    document_title~,
    file_id~,
    start_char_index~,
    end_char_index~,
    start_index~,
    end_index~,
  )
}

///|
/// Create document page citation annotation
pub fn ResponseAnnotation::document_page_citation(
  cited_text~ : String,
  document_index~ : Int,
  document_title~ : String,
  file_id~ : String,
  start_page_number~ : Int,
  end_page_number~ : Int,
  start_index~ : Int,
  end_index~ : Int,
) -> ResponseAnnotation {
  DocumentPageCitation(
    cited_text~,
    document_index~,
    document_title~,
    file_id~,
    start_page_number~,
    end_page_number~,
    start_index~,
    end_index~,
  )
}

///|
/// Create document content-block citation annotation
pub fn ResponseAnnotation::document_content_block_citation(
  cited_text~ : String,
  document_index~ : Int,
  document_title~ : String,
  file_id~ : String,
  start_block_index~ : Int,
  end_block_index~ : Int,
  start_index~ : Int,
  end_index~ : Int,
) -> ResponseAnnotation {
  DocumentContentBlockCitation(
    cited_text~,
    document_index~,
    document_title~,
    file_id~,
    start_block_index~,
    end_block_index~,
    start_index~,
    end_index~,
  )
}

///|
/// Create web search result citation annotation
pub fn ResponseAnnotation::web_search_result_citation(
  cited_text~ : String,
  encrypted_index~ : String,
  title~ : String,
  url~ : String,
  start_index~ : Int,
  end_index~ : Int,
) -> ResponseAnnotation {
  WebSearchResultCitation(
    cited_text~,
    encrypted_index~,
    title~,
    url~,
    start_index~,
    end_index~,
  )
}

///|
/// Create search result citation annotation
pub fn ResponseAnnotation::search_result_citation(
  cited_text~ : String,
  search_result_index~ : Int,
  source~ : String,
  title~ : String,
  start_block_index~ : Int,
  end_block_index~ : Int,
  start_index~ : Int,
  end_index~ : Int,
) -> ResponseAnnotation {
  SearchResultCitation(
    cited_text~,
    search_result_index~,
    source~,
    title~,
    start_block_index~,
    end_block_index~,
    start_index~,
    end_index~,
  )
}

///|
/// Create Gemini grounding citation annotation
pub fn ResponseAnnotation::gemini_grounding_citation(
  chunk_index~ : Int,
  chunk~ : Json,
  support~ : Json,
  cited_text~ : String,
  start_index~ : Int,
  end_index~ : Int,
) -> ResponseAnnotation {
  GeminiGroundingCitation(
    chunk_index~,
    chunk~,
    support~,
    cited_text~,
    start_index~,
    end_index~,
  )
}

///|
pub fn ModelFailure::new(
  type_~ : String,
  message~ : String,
  code? : Int? = None,
  retry_after? : Int? = None,
  payload? : Json? = None,
  body? : String? = None,
) -> ModelFailure {
  { type_, message, code, retry_after, payload, body }
}

///|
pub fn ModelFailure::rate_limited(
  retry_after~ : Int,
  message? : String = "Rate limited",
  code? : Int? = Some(429),
  payload? : Json? = None,
  body? : String? = None,
) -> ModelFailure {
  {
    type_: "rate_limit_error",
    message,
    code,
    retry_after: Some(retry_after),
    payload,
    body,
  }
}

///|
pub fn ModelFailure::parse_error(
  message~ : String,
  payload? : Json? = None,
  body? : String? = None,
) -> ModelFailure {
  {
    type_: "parse_error",
    message,
    code: None,
    retry_after: None,
    payload,
    body,
  }
}

///|
pub fn ModelResponse::as_failure(self : ModelResponse) -> ModelFailure? {
  match self {
    ModelResponse::Failure(failure~) => Some(failure)
    ModelResponse::ModelError(message) =>
      Some(ModelFailure::new(type_="error", message~))
    ModelResponse::RateLimited(retry_after~) =>
      Some(ModelFailure::rate_limited(retry_after~))
    _ => None
  }
}

///|
fn openai_error_type_to_gemini_status_and_code(type_ : String) -> (String, Int) {
  match type_ {
    "invalid_request_error" => ("INVALID_ARGUMENT", 400)
    "authentication_error" => ("UNAUTHENTICATED", 401)
    "permission_error" => ("PERMISSION_DENIED", 403)
    "not_found_error" => ("NOT_FOUND", 404)
    "rate_limit_error" => ("RESOURCE_EXHAUSTED", 429)
    "overloaded_error" => ("UNAVAILABLE", 503)
    "api_error" => ("INTERNAL", 500)
    "content_filter" => ("FAILED_PRECONDITION", 400)
    _ => ("UNKNOWN", 500)
  }
}

///|
pub fn ModelFailure::to_openai_error_json(self : ModelFailure) -> Json {
  let error : Map[String, Json] = {}
  error["message"] = Json::string(self.message)
  error["type"] = Json::string(self.type_)
  match self.code {
    Some(code) => error["code"] = Json::number(code.to_double())
    None => ()
  }
  match self.retry_after {
    Some(retry_after) =>
      error["retry_after"] = Json::number(retry_after.to_double())
    None => ()
  }
  { "error": Json::object(error) }
}

///|
pub fn ModelFailure::to_anthropic_error_json(self : ModelFailure) -> Json {
  let error : Map[String, Json] = {}
  error["type"] = Json::string(self.type_)
  error["message"] = Json::string(self.message)
  match self.code {
    Some(code) => error["code"] = Json::number(code.to_double())
    None => ()
  }
  { "type": "error", "error": Json::object(error) }
}

///|
pub fn ModelFailure::to_gemini_error_json(self : ModelFailure) -> Json {
  let (status, fallback_code) = openai_error_type_to_gemini_status_and_code(
    self.type_,
  )
  let code = match self.code {
    Some(code) => code
    None => fallback_code
  }
  let error : Map[String, Json] = {}
  error["code"] = Json::number(code.to_double())
  error["message"] = Json::string(self.message)
  error["status"] = Json::string(status)
  { "error": Json::object(error) }
}

///|
/// Create tool call trace
pub fn ToolCallTrace::new(
  id~ : String,
  name~ : String,
  kind~ : ToolCallKind,
  statuses~ : Array[ToolCallStatus],
  arguments~ : Json,
) -> ToolCallTrace {
  { id, name, kind, statuses, arguments }
}

///|
/// Create rich text response
pub fn RichTextResponse::new(
  content~ : String,
  content_parts? : Array[ResponseContentPart]? = None,
  annotations? : Array[ResponseAnnotation] = [],
  tool_traces? : Array[ToolCallTrace] = [],
) -> RichTextResponse {
  { content, content_parts, annotations, tool_traces }
}

///|
fn should_preserve_rich_content_parts(
  content_parts : Array[ResponseContentPart],
  annotations : Array[ResponseAnnotation],
  tool_traces : Array[ToolCallTrace],
) -> Bool {
  if annotations.length() > 0 ||
    tool_traces.length() > 0 ||
    content_parts.length() > 1 {
    return true
  }
  for part in content_parts {
    match part {
      ResponseContentPart::OutputText(_) => ()
      _ => return true
    }
  }
  false
}

///|
/// Build a RichTextResponse from parsed content parts.
/// Keeps structured parts only when needed to preserve fidelity.
pub fn RichTextResponse::from_parts(
  content~ : String,
  content_parts~ : Array[ResponseContentPart],
  annotations? : Array[ResponseAnnotation] = [],
  tool_traces? : Array[ToolCallTrace] = [],
) -> RichTextResponse {
  let structured_parts = if content_parts.length() > 0 &&
    should_preserve_rich_content_parts(content_parts, annotations, tool_traces) {
    Some(content_parts)
  } else {
    None
  }
  { content, content_parts: structured_parts, annotations, tool_traces }
}

///|
/// Create new ToolDefinition
pub fn ToolDefinition::new(
  name~ : String,
  description~ : String,
  parameters~ : Json,
) -> ToolDefinition {
  {
    kind: ToolDefinitionKind::Function,
    name,
    description,
    parameters,
    schema: None,
    metadata: {},
  }
}

///|
/// Create generic builtin tool definition
pub fn ToolDefinition::builtin(
  type_~ : String,
  name? : String = "",
  description? : String = "",
  config? : Json = Json::object({}),
) -> ToolDefinition {
  {
    kind: ToolDefinitionKind::Builtin(builtin_type=type_, config~),
    name,
    description,
    parameters: Json::object({}),
    schema: None,
    metadata: {},
  }
}

///|
/// Create OpenAI web_search_preview tool
pub fn ToolDefinition::web_search_preview(
  search_context_size? : String? = None,
  user_location_country? : String? = None,
) -> ToolDefinition {
  {
    kind: ToolDefinitionKind::WebSearchPreview(
      search_context_size~,
      user_location_country~,
    ),
    name: web_search_tool_name(),
    description: web_search_tool_description(),
    parameters: Json::object({}),
    schema: None,
    metadata: {},
  }
}

///|
/// Create OpenAI web_search_preview_2025_03_11 tool
pub fn ToolDefinition::web_search_preview_2025_03_11(
  search_context_size? : String? = None,
  user_location_country? : String? = None,
) -> ToolDefinition {
  {
    kind: ToolDefinitionKind::WebSearchPreview20250311(
      search_context_size~,
      user_location_country~,
    ),
    name: web_search_tool_name(),
    description: web_search_tool_description(),
    parameters: Json::object({}),
    schema: None,
    metadata: {},
  }
}

///|
/// Build JSON Schema helper
pub fn build_json_schema(
  type_~ : String,
  properties~ : Map[String, Json],
  required~ : Array[String],
) -> Json {
  {
    "type": type_,
    "properties": Json::object(properties),
    "required": Json::array(required.map(fn(s) { Json::string(s) })),
  }
}
