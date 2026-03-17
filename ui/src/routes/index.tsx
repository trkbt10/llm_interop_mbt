import { useState, useRef, useCallback, useEffect, useMemo } from "react";
import type { ChatMessage, ChatMessageDisplayHandle } from "react-editor-ui/chat/ChatMessageDisplay";
import { GridLayout } from "react-panel-layout";
import type { PanelLayoutConfig, LayerDefinition } from "react-panel-layout";
import { fetchModels, fetchHealth, sendChat, settingsToRequestOptions, type Model, modelKey, modelIdFromKey } from "../api/client";
import { surfaceToDialect, type DialectName } from "../api/dialects";
import { toContentParts } from "../utils/responseContent";
import { ChatMessages } from "../components/ChatMessages";
import { ChatInputArea } from "../components/ChatInputArea";
import { SettingsPanel, defaultChatSettings, type ChatSettings } from "../components/SettingsPanel";
import { useAttachments, readFileAsBase64 } from "../hooks/useAttachments";

type ContentPart = { type: "text"; text: string } | { type: "image"; url: string };

const layoutConfig: PanelLayoutConfig = {
  areas: [["settings", "chat"]],
  rows: [{ size: "1fr" }],
  columns: [
    { size: "360px", resizable: true, minSize: 280, maxSize: 520 },
    { size: "1fr" },
  ],
};

export function IndexPage() {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [inputValue, setInputValue] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [models, setModels] = useState<Model[]>([]);
  const [selectedModel, setSelectedModel] = useState("");
  const [dialect, setDialect] = useState<DialectName>("openai-chat-completion");
  const [settings, setSettings] = useState<ChatSettings>(defaultChatSettings);
  const displayRef = useRef<ChatMessageDisplayHandle>(null);
  const attachments = useAttachments();

  useEffect(() => {
    fetchHealth()
      .then((res) => {
        setDialect(surfaceToDialect(res.dialect));
      })
      .catch((err: unknown) => {
        console.error("Failed to fetch health:", err);
      });

    fetchModels()
      .then((res) => {
        setModels(res.data);
        if (res.data.length > 0) {
          setSelectedModel(modelKey(res.data[0]));
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

    if (!hasContent || isLoading || !selectedModel) {
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
      const response = await sendChat(
        dialect,
        newMessages,
        modelIdFromKey(selectedModel),
        settingsToRequestOptions(settings),
      );

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
  }, [inputValue, isLoading, messages, selectedModel, dialect, attachments, settings]);

  const files = attachments.attachments.map((a) => a.file);
  const canSend =
    (!!inputValue.trim() || files.length > 0) && !isLoading && !!selectedModel;

  const layers: LayerDefinition[] = useMemo(
    () => [
      {
        id: "settings",
        gridArea: "settings",
        scrollable: true,
        component: (
          <SettingsPanel
            models={models}
            selectedModel={selectedModel}
            onModelChange={setSelectedModel}
            dialect={dialect}
            onDialectChange={setDialect}
            settings={settings}
            onSettingsChange={setSettings}
          />
        ),
      },
      {
        id: "chat",
        gridArea: "chat",
        component: (
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              height: "100%",
              overflow: "hidden",
            }}
          >
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
        ),
      },
    ],
    [
      models, selectedModel, dialect, settings,
      messages, isLoading, inputValue, canSend, files,
      attachments.add, attachments.removeAt, handleSend,
    ],
  );

  return (
    <GridLayout
      config={layoutConfig}
      layers={layers}
      root
      style={{
        height: "100vh",
        backgroundColor: "var(--rei-color-surface)",
        color: "var(--rei-color-text)",
      }}
    />
  );
}
