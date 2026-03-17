import type { ContentPart } from "react-editor-ui/chat/ChatMessageDisplay";
import type { ResponseChoice, ResponseContentBlock } from "../api/dialects/types";
import { buildDataUrl } from "./dataUrl";

/**
 * Extract all text from a choice's content blocks, joining with newlines.
 */
export function extractText(choice: ResponseChoice): string {
  return choice.content
    .filter((block): block is ResponseContentBlock & { type: "text" } => block.type === "text")
    .map((block) => block.text)
    .join("\n");
}

/**
 * Convert a single ResponseContentBlock to a react-editor-ui ContentPart.
 *
 * Uses native content types (text, image, audio, file) where react-editor-ui
 * has built-in renderers. Falls back to CustomContentPart for types that
 * only exist in LLM APIs (tool_call, reasoning, etc.).
 */
export function toContentPart(block: ResponseContentBlock): ContentPart {
  switch (block.type) {
    case "text": {
      return { type: "text", text: block.text };
    }
    case "image": {
      const url = block.url ?? (block.data ? buildDataUrl(block.mimeType ?? "image/png", block.data) : "");
      return { type: "image", url };
    }
    case "audio": {
      const url = buildDataUrl(block.mimeType ?? "audio/mp3", block.data);
      return { type: "audio", url };
    }
    case "file": {
      return {
        type: "file",
        name: block.name ?? block.fileId ?? block.fileUri ?? "file",
        url: block.fileUri,
        mimeType: block.mimeType,
      };
    }
    default: {
      // tool_call, tool_result, web_search, code_execution,
      // code_execution_result, reasoning, refusal
      return {
        type: "custom",
        contentType: block.type,
        data: block,
      };
    }
  }
}

/**
 * Convert a ResponseChoice's content blocks to react-editor-ui ContentPart[].
 */
export function toContentParts(choice: ResponseChoice): ContentPart[] {
  return choice.content.map(toContentPart);
}
