import type { ChatMessage } from "react-editor-ui/chat/ChatMessageDisplay";

// ---------------------------------------------------------------------------
// Input content (for building requests from ChatMessage)
// ---------------------------------------------------------------------------

export type ContentPart = { type: string; text?: string; url?: string };

// ---------------------------------------------------------------------------
// Response content blocks — rich union covering all API formats
// ---------------------------------------------------------------------------

export type UrlCitation = {
  type: "url_citation";
  url: string;
  title?: string;
  startIndex: number;
  endIndex: number;
};

export type Annotation = UrlCitation;

export type TextBlock = {
  type: "text";
  text: string;
  annotations?: Annotation[];
};

export type ImageBlock = {
  type: "image";
  url?: string;
  mimeType?: string;
  data?: string;
};

export type AudioBlock = {
  type: "audio";
  data: string;
  mimeType?: string;
};

export type FileBlock = {
  type: "file";
  fileId?: string;
  fileUri?: string;
  mimeType?: string;
  name?: string;
};

export type ToolCallBlock = {
  type: "tool_call";
  id: string;
  name: string;
  arguments: string;
};

export type ToolResultBlock = {
  type: "tool_result";
  toolCallId: string;
  content: ResponseContentBlock[];
  isError?: boolean;
};

export type WebSearchBlock = {
  type: "web_search";
  id: string;
  query: string;
  status: string;
};

export type CodeExecutionBlock = {
  type: "code_execution";
  language: string;
  code: string;
};

export type CodeExecutionResultBlock = {
  type: "code_execution_result";
  output: string;
  outcome?: string;
};

export type ReasoningBlock = {
  type: "reasoning";
  text: string;
};

export type RefusalBlock = {
  type: "refusal";
  refusal: string;
};

export type ResponseContentBlock =
  | TextBlock
  | ImageBlock
  | AudioBlock
  | FileBlock
  | ToolCallBlock
  | ToolResultBlock
  | WebSearchBlock
  | CodeExecutionBlock
  | CodeExecutionResultBlock
  | ReasoningBlock
  | RefusalBlock;

// ---------------------------------------------------------------------------
// Response choice — one candidate/choice from the model
// ---------------------------------------------------------------------------

export type ResponseChoice = {
  content: ResponseContentBlock[];
};

// ---------------------------------------------------------------------------
// Top-level response
// ---------------------------------------------------------------------------

export type ModelResponse = {
  id: string;
  choices: ResponseChoice[];
};

// ---------------------------------------------------------------------------
// Dialect interface
// ---------------------------------------------------------------------------

export type DialectName = "openai-chat-completion" | "openai-responses-api" | "anthropic-messages-api" | "gemini-generate-content";

export type RequestOptions = {
  maxTokens?: number;
  temperature?: number;
  topP?: number;
  topK?: number;
  stop?: string[];
  stream?: boolean;
};

/** Which optional parameters a dialect supports */
export type SupportedParams = {
  maxTokens: boolean;
  temperature: boolean;
  topP: boolean;
  topK: boolean;
  stop: boolean;
};

export type Dialect = {
  readonly name: DialectName;
  readonly supportedParams: SupportedParams;
  buildEndpoint: (model: string) => string;
  buildRequest: (
    messages: ChatMessage[],
    model: string,
    options?: RequestOptions
  ) => unknown;
  parseResponse: (response: unknown) => ModelResponse;
};
