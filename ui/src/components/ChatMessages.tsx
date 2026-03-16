import type { RefObject } from "react";
import {
  ChatMessageDisplay,
  type ChatMessage,
  type ChatMessageDisplayHandle,
} from "react-editor-ui/chat/ChatMessageDisplay";

type ChatMessagesProps = {
  messages: ChatMessage[];
  isLoading: boolean;
  displayRef: RefObject<ChatMessageDisplayHandle | null>;
};

export function ChatMessages({ messages, isLoading, displayRef }: ChatMessagesProps) {
  return (
    <div style={{ flex: 1, overflow: "hidden" }}>
      <ChatMessageDisplay.Root
        ref={displayRef}
        messages={messages}
        height="100%"
        isThinking={isLoading}
        displayOptions={{
          variant: "bubble",
          showTimestamp: false,
        }}
        renderActions={(message) => {
          if (message.role !== "assistant") {
            return [];
          }
          return [
            {
              id: "copy",
              icon: "\u{1F4CB}",
              label: "Copy",
              onClick: () => {
                const text = typeof message.content === "string" ? message.content : "";
                void navigator.clipboard.writeText(text);
              },
            },
          ];
        }}
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
