import { useState, useRef, useCallback, useEffect } from "react";
import type { ChatMessage, ChatMessageDisplayHandle } from "react-editor-ui/chat/ChatMessageDisplay";
import { fetchModels, fetchHealth, sendChat, type Model } from "../api/client";
import { toContentParts } from "../utils/responseContent";
import { ChatHeader } from "../components/ChatHeader";
import { ChatMessages } from "../components/ChatMessages";
import { ChatInputArea } from "../components/ChatInputArea";
import { useAttachments, readFileAsBase64 } from "../hooks/useAttachments";

type ContentPart = { type: "text"; text: string } | { type: "image"; url: string };

export function IndexPage() {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [inputValue, setInputValue] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [models, setModels] = useState<Model[]>([]);
  const [selectedModel, setSelectedModel] = useState("");
  const [dialect, setDialect] = useState("");
  const displayRef = useRef<ChatMessageDisplayHandle>(null);
  const attachments = useAttachments();

  useEffect(() => {
    fetchHealth()
      .then((res) => {
        setDialect(res.dialect);
      })
      .catch((err: unknown) => {
        console.error("Failed to fetch health:", err);
      });

    fetchModels()
      .then((res) => {
        setModels(res.data);
        if (res.data.length > 0) {
          setSelectedModel(res.data[0].id);
        }
      })
      .catch((err: unknown) => {
        console.error("Failed to fetch models:", err);
      });
  }, []);

  const handleSend = useCallback(async () => {
    const text = inputValue.trim();
    const files = attachments.attachments;
    const hasContent = text || files.length > 0;

    if (!hasContent || isLoading || !selectedModel || !dialect) {
      return;
    }

    const contentParts: ContentPart[] = [];
    if (text) {
      contentParts.push({ type: "text", text });
    }
    for (const { file } of files) {
      if (file.type.startsWith("image/")) {
        const dataUrl = await readFileAsBase64(file);
        contentParts.push({ type: "image", url: dataUrl });
      }
    }

    const userMessage: ChatMessage = {
      id: crypto.randomUUID(),
      role: "user",
      content:
        contentParts.length === 1 && contentParts[0].type === "text"
          ? contentParts[0].text
          : contentParts,
    };

    const newMessages = [...messages, userMessage];
    setMessages(newMessages);
    setInputValue("");
    attachments.clear();
    setIsLoading(true);
    setTimeout(() => displayRef.current?.scrollToBottom(), 0);

    try {
      const response = await sendChat(dialect, newMessages, selectedModel, {
        maxTokens: 4096,
      });

      const firstChoice = response.choices[0] as typeof response.choices[number] | undefined;
      if (firstChoice && firstChoice.content.length > 0) {
        setMessages((prev) => [
          ...prev,
          {
            id: response.id || crypto.randomUUID(),
            role: "assistant",
            content: toContentParts(firstChoice),
          },
        ]);
        setTimeout(() => displayRef.current?.scrollToBottom(), 0);
      }
    } catch (err) {
      setMessages((prev) => [
        ...prev,
        {
          id: crypto.randomUUID(),
          role: "assistant",
          content: `Error: ${err instanceof Error ? err.message : "Unknown error"}`,
        },
      ]);
    } finally {
      setIsLoading(false);
    }
  }, [inputValue, isLoading, messages, selectedModel, dialect, attachments]);

  const files = attachments.attachments.map((a) => a.file);
  const canSend =
    (!!inputValue.trim() || files.length > 0) && !isLoading && !!selectedModel && !!dialect;

  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        height: "100vh",
        backgroundColor: "var(--rei-color-surface)",
        color: "var(--rei-color-text)",
      }}
    >
      <ChatHeader
        dialect={dialect}
        models={models}
        selectedModel={selectedModel}
        onModelChange={setSelectedModel}
      />
      <ChatMessages displayRef={displayRef} messages={messages} isLoading={isLoading} />
      <ChatInputArea
        value={inputValue}
        onChange={setInputValue}
        onSend={() => void handleSend()}
        isLoading={isLoading}
        canSend={canSend}
        attachedFiles={files}
        onFileSelect={attachments.add}
        onFileRemove={attachments.removeAt}
      />
    </div>
  );
}
