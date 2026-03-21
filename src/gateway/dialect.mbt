///|
/// ModelApi → DialectSpec resolution and GatewaySurface route dispatch

// =============================================================================
// ModelApi → DialectSpec
// =============================================================================

///|
/// Resolve a ModelApi to its full protocol specification
pub fn ModelApi::to_spec(self : ModelApi) -> DialectSpec {
  match self {
    OpenAICompletions =>
      {
        id: "openai-completions",
        default_base_url: @openai.chat_completions_default_base_url(),
        surface: OpenAI,
        completion_path: fn(base, _model, _key) {
          @openai.chat_completions_path(base)
        },
        models_path: fn(base, _key) {
          @openai.chat_completions_models_path(base)
        },
        auth_headers: @openai.chat_completions_auth_headers,
      }
    OpenAIResponses =>
      {
        id: "openai-responses",
        default_base_url: @openai.responses_api_default_base_url(),
        surface: OpenAI,
        completion_path: fn(base, _model, _key) {
          @openai.responses_api_path(base)
        },
        models_path: fn(base, _key) {
          @openai.chat_completions_models_path(base)
        },
        auth_headers: @openai.chat_completions_auth_headers,
      }
    AnthropicMessages =>
      {
        id: "anthropic-messages",
        default_base_url: @anthropic.default_base_url(),
        surface: Anthropic,
        completion_path: fn(base, _model, _key) {
          @anthropic.anthropic_completion_path(base)
        },
        models_path: fn(base, _key) {
          @openai.chat_completions_models_path(base)
        },
        auth_headers: @anthropic.auth_headers,
      }
    GoogleGenerativeAI =>
      {
        id: "google-generative-ai",
        default_base_url: @gemini.default_base_url(),
        surface: Gemini,
        completion_path: @gemini.completion_path,
        models_path: @gemini.models_path,
        auth_headers: fn(_key) { @gemini.auth_headers() },
      }
    GithubCopilot =>
      {
        id: "github-copilot",
        default_base_url: @openai.github_copilot_default_base_url(),
        surface: OpenAI,
        completion_path: fn(base, _model, _key) {
          @openai.chat_completions_path(base)
        },
        models_path: fn(base, _key) {
          @openai.chat_completions_models_path(base)
        },
        auth_headers: @openai.chat_completions_auth_headers,
      }
    BedrockConverseStream =>
      {
        id: "bedrock-converse-stream",
        default_base_url: "",
        surface: OpenAI,
        completion_path: fn(base, _model, _key) {
          @openai.chat_completions_path(base)
        },
        models_path: fn(base, _key) {
          @openai.chat_completions_models_path(base)
        },
        auth_headers: @openai.chat_completions_auth_headers,
      }
    Ollama =>
      {
        id: "ollama",
        default_base_url: @openai.ollama_default_base_url(),
        surface: OpenAI,
        completion_path: fn(base, _model, _key) {
          @openai.chat_completions_path(base)
        },
        models_path: fn(base, _key) {
          @openai.chat_completions_models_path(base)
        },
        auth_headers: @openai.chat_completions_auth_headers,
      }
    OpenRouter =>
      {
        id: "openrouter",
        default_base_url: @openai.openrouter_default_base_url(),
        surface: OpenAI,
        completion_path: fn(base, _model, _key) {
          @openai.chat_completions_path(base)
        },
        models_path: fn(base, _key) {
          @openai.chat_completions_models_path(base)
        },
        auth_headers: @openai.chat_completions_auth_headers,
      }
    CodexAppServer =>
      {
        id: "codex-app-server",
        default_base_url: @codex.default_base_url(),
        surface: Codex,
        completion_path: fn(base, _model, _key) { base },
        models_path: fn(base, _key) { base },
        auth_headers: @codex.auth_headers,
      }
    ClaudeMcpServe =>
      {
        id: "claude-mcp-serve",
        default_base_url: @claude_mcp.default_base_url(),
        surface: OpenAI, // `claude mcp serve` is a backend; route via OpenAI surface
        completion_path: fn(base, _model, _key) { base },
        models_path: fn(base, _key) { base },
        auth_headers: @claude_mcp.auth_headers,
      }
  }
}

///|
/// Convenience: get GatewaySurface from ModelApi
pub fn ModelApi::to_dialect(self : ModelApi) -> GatewaySurface {
  self.to_spec().surface
}

///|
/// Whether this provider natively supports the Responses API (/v1/responses).
/// Only OpenAI's own Responses API variant returns true.
/// Other providers (Ollama, Groq, OpenRouter, etc.) use Chat Completions
/// and require translation if the caller wants Responses API semantics.
pub fn ModelApi::supports_responses_api(self : ModelApi) -> Bool {
  match self {
    OpenAIResponses => true
    _ => false
  }
}

///|
/// Convenience: get default base URL
pub fn ModelApi::default_base_url(self : ModelApi) -> String {
  self.to_spec().default_base_url
}

///|
/// Convenience: build completion path
pub fn ModelApi::completion_path(
  self : ModelApi,
  base_path : String,
  model : String,
  api_key : String,
) -> String {
  (self.to_spec().completion_path)(base_path, model, api_key)
}

///|
/// Convenience: build models path
pub fn ModelApi::models_path(
  self : ModelApi,
  base_path : String,
  api_key : String,
) -> String {
  (self.to_spec().models_path)(base_path, api_key)
}

///|
/// Convenience: build auth headers
pub fn ModelApi::auth_headers(
  self : ModelApi,
  api_key : String,
) -> Map[String, String] {
  (self.to_spec().auth_headers)(api_key)
}

// =============================================================================
// GatewaySurface route dispatch
// =============================================================================

///|
/// Resolve a completion route for the given HTTP method, path, and body.
pub fn GatewaySurface::resolve_completion(
  self : GatewaySurface,
  meth : String,
  path : String,
  body : String,
) -> RouteResult? {
  match self {
    OpenAI => {
      match @openai.chat_completions_resolve(meth, path, body) {
        Some((_, b)) => return Some(Completion(dialect=OpenAI, body=b))
        None => ()
      }
      match @openai.responses_api_resolve(meth, path, body) {
        Some((_, b)) => Some(ResponsesApi(body=b))
        None => None
      }
    }
    Anthropic =>
      match @anthropic.anthropic_resolve_completion(meth, path, body) {
        Some((_, _, b)) => Some(Completion(dialect=Anthropic, body=b))
        None => None
      }
    Gemini =>
      match @gemini.resolve_completion(meth, path, body) {
        Some((_, model, b)) =>
          Some(CompletionWithModel(dialect=Gemini, model~, body=b))
        None => None
      }
    Codex =>
      // Codex is a backend-only surface; inbound routing delegates to OpenAI surface
      match @openai.chat_completions_resolve(meth, path, body) {
        Some((_, b)) => Some(Completion(dialect=Codex, body=b))
        None => None
      }
  }
}
