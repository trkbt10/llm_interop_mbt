///|
/// Gateway types for LLM API proxy
/// Based on openclaw provider configuration structure

///|
/// Gateway errors
pub(all) suberror GatewayError {
  ConfigError(String)
  BackendNotFound(String)
  InvalidRequest(String)
  UpstreamError(code~ : Int, message~ : String)
  NetworkError(String)
} derive(Show)

///|
/// Model API format
pub(all) enum ModelApi {
  OpenAICompletions // OpenAI chat completions API
  OpenAIResponses // OpenAI responses API (new)
  AnthropicMessages // Anthropic messages API
  GoogleGenerativeAI // Google Gemini API
  GithubCopilot // GitHub Copilot API
  BedrockConverseStream // AWS Bedrock converse stream
  Ollama // Ollama local API
  CodexAppServer // Codex app-server JSON-RPC API
} derive(Show, Eq)

///|
pub fn ModelApi::from_string(s : String) -> ModelApi? {
  match s.to_lower() {
    "openai-completions" | "openai" => Some(OpenAICompletions)
    "openai-responses" => Some(OpenAIResponses)
    "anthropic-messages" | "anthropic" | "claude" => Some(AnthropicMessages)
    "google-generative-ai" | "gemini" | "google" => Some(GoogleGenerativeAI)
    "github-copilot" | "copilot" => Some(GithubCopilot)
    "bedrock-converse-stream" | "bedrock" => Some(BedrockConverseStream)
    "ollama" => Some(Ollama)
    "codex-app-server" | "codex" => Some(CodexAppServer)
    _ => None
  }
}

///|
pub fn ModelApi::to_string(self : ModelApi) -> String {
  match self {
    OpenAICompletions => "openai-completions"
    OpenAIResponses => "openai-responses"
    AnthropicMessages => "anthropic-messages"
    GoogleGenerativeAI => "google-generative-ai"
    GithubCopilot => "github-copilot"
    BedrockConverseStream => "bedrock-converse-stream"
    Ollama => "ollama"
    CodexAppServer => "codex-app-server"
  }
}

///|
/// Authentication mode
pub(all) enum AuthMode {
  ApiKey
  AwsSdk
  OAuth
  Token
} derive(Show, Eq)

///|
pub fn AuthMode::from_string(s : String) -> AuthMode? {
  match s.to_lower() {
    "api-key" | "apikey" | "api_key" => Some(ApiKey)
    "aws-sdk" | "aws" => Some(AwsSdk)
    "oauth" => Some(OAuth)
    "token" => Some(Token)
    _ => None
  }
}

///|
/// Input modality
pub(all) enum InputModality {
  Text
  Image
} derive(Show, Eq)

///|
/// Model compatibility configuration
pub(all) struct ModelCompatConfig {
  supports_store : Bool
  supports_developer_role : Bool
  supports_reasoning_effort : Bool
  supports_usage_in_streaming : Bool
  supports_strict_mode : Bool
  max_tokens_field : String // "max_completion_tokens" or "max_tokens"
  thinking_format : String // "openai", "zai", "qwen"
  requires_tool_result_name : Bool
  requires_assistant_after_tool_result : Bool
  requires_thinking_as_text : Bool
  requires_mistral_tool_ids : Bool
} derive(Show)

///|
pub fn ModelCompatConfig::default() -> ModelCompatConfig {
  {
    supports_store: false,
    supports_developer_role: false,
    supports_reasoning_effort: false,
    supports_usage_in_streaming: false,
    supports_strict_mode: false,
    max_tokens_field: "max_tokens",
    thinking_format: "",
    requires_tool_result_name: false,
    requires_assistant_after_tool_result: false,
    requires_thinking_as_text: false,
    requires_mistral_tool_ids: false,
  }
}

///|
/// Token cost configuration (per million tokens)
pub(all) struct TokenCost {
  input : Double
  output : Double
  cache_read : Double
  cache_write : Double
} derive(Show)

///|
pub fn TokenCost::default() -> TokenCost {
  { input: 0.0, output: 0.0, cache_read: 0.0, cache_write: 0.0 }
}

///|
/// Model definition configuration
pub(all) struct ModelConfig {
  id : String
  name : String
  api : ModelApi? // Override provider's default API
  reasoning : Bool // Supports extended thinking
  input : Array[InputModality]
  cost : TokenCost
  context_window : Int
  max_tokens : Int
  headers : Map[String, String]
  compat : ModelCompatConfig
} derive(Show)

///|
pub fn ModelConfig::new(id : String) -> ModelConfig {
  {
    id,
    name: id,
    api: None,
    reasoning: false,
    input: [Text],
    cost: TokenCost::default(),
    context_window: 128000,
    max_tokens: 4096,
    headers: {},
    compat: ModelCompatConfig::default(),
  }
}

///|
/// Provider configuration
pub(all) struct ProviderConfig {
  id : String
  base_url : String
  api_key : String
  auth : AuthMode
  api : ModelApi // Default API for this provider
  headers : Map[String, String]
  auth_header : Bool // Include auth in header
  models : Array[ModelConfig]
  model_patterns : Array[String] // Prefix patterns for fallback routing (e.g. ["claude-"])
} derive(Show)

///|
pub fn ProviderConfig::new(id : String, api : ModelApi) -> ProviderConfig {
  {
    id,
    base_url: "",
    api_key: "",
    auth: ApiKey,
    api,
    headers: {},
    auth_header: true,
    models: [],
    model_patterns: [],
  }
}

///|
/// Legacy backend configuration (for backwards compatibility)
pub(all) struct BackendConfig {
  id : String
  provider : ProviderConfig
  weight : Int
} derive(Show)

///|
/// Server configuration
pub(all) struct ServerConfig {
  port : Int
  host : String
} derive(Show)

///|
/// Models configuration mode
pub(all) enum ConfigMode {
  Merge // Merge with built-in providers
  Replace // Replace all providers
} derive(Show, Eq)

///|
/// Full gateway configuration
pub(all) struct GatewayConfig {
  mode : ConfigMode
  providers : Map[String, ProviderConfig]
  backends : Array[BackendConfig] // Legacy format support
  server : ServerConfig
} derive(Show)

///|
pub fn GatewayConfig::default() -> GatewayConfig {
  {
    mode: Merge,
    providers: {},
    backends: [],
    server: { port: 18080, host: "0.0.0.0" },
  }
}

///|
/// Gateway surface type (which API dialect to expose)
pub(all) enum GatewaySurface {
  OpenAI
  Anthropic
  Gemini
} derive(Show, Eq)

///|
pub fn GatewaySurface::from_string(s : String) -> GatewaySurface? {
  match s.to_lower() {
    "openai" => Some(OpenAI)
    "anthropic" | "claude" => Some(Anthropic)
    "gemini" | "google" => Some(Gemini)
    _ => None
  }
}

///|
pub fn GatewaySurface::to_string(self : GatewaySurface) -> String {
  match self {
    OpenAI => "openai"
    Anthropic => "anthropic"
    Gemini => "gemini"
  }
}
