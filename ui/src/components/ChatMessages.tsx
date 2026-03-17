import { useMemo, type RefObject } from "react";
import {
  ChatMessageDisplay,
  type ChatMessage,
  type ChatMessageDisplayHandle,
  type ContentPartComponentMap,
} from "react-editor-ui/chat/ChatMessageDisplay";
import { Copy } from "lucide-react";
import { CustomContentPartRenderer } from "./blocks";
import { ConstrainedImageRenderer } from "./blocks/ConstrainedImageRenderer";
import { ICON_SIZE } from "./iconSize";

type ChatMessagesProps = {
  messages: ChatMessage[];
  isLoading: boolean;
  displayRef: RefObject<ChatMessageDisplayHandle | null>;
};

const contentComponents: ContentPartComponentMap = {
  image: ConstrainedImageRenderer,
  custom: CustomContentPartRenderer,
};

export function ChatMessages({ messages, isLoading, displayRef }: ChatMessagesProps) {
  const renderActions = useMemo(
    () => (message: ChatMessage) => {
      if (message.role !== "assistant") {
        return [];
      }
      return [
        {
          id: "copy",
          icon: <Copy size={ICON_SIZE.action} />,
          label: "Copy",
          onClick: () => {
            if (typeof message.content === "string") {
              void navigator.clipboard.writeText(message.content);
              return;
            }
            // Extract text from custom content parts (ResponseContentBlock[])
            const texts: string[] = [];
            for (const part of message.content) {
              if (part.type === "text") {
                texts.push(part.text);
              }
              if (part.type === "custom" && part.contentType === "tool_call") {
                // skip non-text blocks for copy
              }
            }
            void navigator.clipboard.writeText(texts.join("\n"));
          },
        },
      ];
    },
    [],
  );

  return (
    <div style={{ flex: 1, overflow: "hidden" }}>
      <ChatMessageDisplay.Root
        ref={displayRef}
        messages={messages}
        height="100%"
        isThinking={isLoading}
        contentComponents={contentComponents}
        displayOptions={{
          variant: "bubble",
          showTimestamp: false,
        }}
        renderActions={renderActions}
      >
        <ChatMessageDisplay.Overlay visible={messages.length === 0}>
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              justifyContent: "center",
              height: "100%",
              color: "var(--rei-color-text-muted)",
              gap: "var(--rei-space-md)",
            }}
          >
            <p style={{ fontSize: "var(--rei-size-font-lg)" }}>LLM Gateway</p>
            <p>Select a model and start chatting</p>
          </div>
        </ChatMessageDisplay.Overlay>
      </ChatMessageDisplay.Root>
    </div>
  );
}
