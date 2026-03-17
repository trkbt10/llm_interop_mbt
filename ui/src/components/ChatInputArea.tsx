import { useRef } from "react";
import { ChatInput, SendButton, FilePreview } from "react-editor-ui/chat/ChatInput";
import { IconButton } from "react-editor-ui/IconButton";
import { Paperclip } from "lucide-react";
import { ICON_SIZE } from "./iconSize";

type ChatInputAreaProps = {
  value: string;
  onChange: (value: string) => void;
  onSend: () => void;
  isLoading: boolean;
  canSend: boolean;
  attachedFiles: File[];
  onFileSelect: (files: File[]) => void;
  onFileRemove: (index: number) => void;
};

export function ChatInputArea({
  value,
  onChange,
  onSend,
  isLoading,
  canSend,
  attachedFiles,
  onFileSelect,
  onFileRemove,
}: ChatInputAreaProps) {
  const fileInputRef = useRef<HTMLInputElement>(null);

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      onSend();
    }
  };

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = e.target.files;
    if (files) {
      onFileSelect([...files]);
    }
    e.target.value = "";
  };

  return (
    <div style={{ padding: "var(--rei-space-lg) var(--rei-space-xl)" }}>
      <input
        type="file"
        ref={fileInputRef}
        onChange={handleFileChange}
        accept="image/*"
        multiple
        style={{ display: "none" }}
      />
      <ChatInput.Root variant="default">
        {attachedFiles.length > 0 && (
          <ChatInput.Badges>
            {attachedFiles.map((file, index) => (
              <FilePreview
                key={`${file.name}-${index}`}
                file={file}
                onRemove={() => onFileRemove(index)}
              />
            ))}
          </ChatInput.Badges>
        )}
        <ChatInput.Content>
          <textarea
            value={value}
            onChange={(e) => onChange(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="Type a message..."
            disabled={isLoading}
            style={{
              width: "100%",
              minHeight: "44px",
              maxHeight: "200px",
              padding: "var(--rei-space-md) var(--rei-space-lg)",
              border: "none",
              background: "transparent",
              color: "inherit",
              fontSize: "var(--rei-size-font-md)",
              lineHeight: "1.5",
              resize: "none",
              outline: "none",
              fontFamily: "inherit",
            }}
          />
        </ChatInput.Content>
        <ChatInput.Toolbar>
          <IconButton
            icon={<Paperclip size={ICON_SIZE.toolbar} />}
            aria-label="Attach image"
            onClick={() => fileInputRef.current?.click()}
            disabled={isLoading}
          />
          <SendButton onClick={onSend} canSend={canSend} isLoading={isLoading} />
        </ChatInput.Toolbar>
      </ChatInput.Root>
    </div>
  );
}
