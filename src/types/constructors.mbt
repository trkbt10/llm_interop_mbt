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
  annotations? : Array[ResponseAnnotation] = [],
  tool_traces? : Array[ToolCallTrace] = [],
) -> RichTextResponse {
  { content, annotations, tool_traces }
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
