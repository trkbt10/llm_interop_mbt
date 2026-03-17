import { useCallback, useRef } from "react";
import { useStreamingContent } from "react-editor-ui/chat/ChatMessageDisplay";
import type { ResponseContentBlock } from "../api/dialects/types";
import { toContentPart } from "../utils/responseContent";

export type UseStreamingChatReturn = {
  /** Current content parts for the streaming message */
  parts: ReturnType<typeof useStreamingContent>["parts"];
  /** Whether streaming is in progress */
  isStreaming: boolean;
  /** Memoized text content */
  textContent: string;
  /** Append a text delta from SSE */
  appendTextDelta: (chunk: string) => void;
  /** Append a complete non-text block (tool_call, web_search, etc.) */
  appendBlock: (block: ResponseContentBlock) => void;
  /** Mark streaming as complete */
  complete: () => void;
  /** Reset for a new streaming session */
  reset: () => void;
};

/**
 * Hook that bridges ResponseContentBlock streaming with react-editor-ui's
 * useStreamingContent. Handles text deltas efficiently via appendText,
 * and non-text blocks via appendPart with toContentPart conversion.
 */
export function useStreamingChat(): UseStreamingChatReturn {
  const streaming = useStreamingContent();
  const lastBlockTypeRef = useRef<string | null>(null);

  const appendTextDelta = useCallback(
    (chunk: string) => {
      lastBlockTypeRef.current = "text";
      streaming.appendText(chunk);
    },
    [streaming]
  );

  const appendBlock = useCallback(
    (block: ResponseContentBlock) => {
      lastBlockTypeRef.current = block.type;
      streaming.appendPart(toContentPart(block));
    },
    [streaming]
  );

  const reset = useCallback(() => {
    lastBlockTypeRef.current = null;
    streaming.reset();
  }, [streaming]);

  return {
    parts: streaming.parts,
    isStreaming: streaming.isStreaming,
    textContent: streaming.textContent,
    appendTextDelta,
    appendBlock,
    complete: streaming.complete,
    reset,
  };
}
