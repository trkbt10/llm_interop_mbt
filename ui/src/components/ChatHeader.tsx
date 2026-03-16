import { Select } from "react-editor-ui/Select";
import type { Model } from "../api/client";

type ChatHeaderProps = {
  dialect: string;
  models: Model[];
  selectedModel: string;
  onModelChange: (model: string) => void;
};

export function ChatHeader({
  dialect,
  models,
  selectedModel,
  onModelChange,
}: ChatHeaderProps) {
  return (
    <header
      style={{
        padding: "var(--rei-space-lg) var(--rei-space-xl)",
        borderBottom: "1px solid var(--rei-color-border)",
        display: "flex",
        alignItems: "center",
        gap: "var(--rei-space-lg)",
      }}
    >
      <h1 style={{ margin: 0, fontSize: "var(--rei-size-font-lg)", fontWeight: 600 }}>
        LLM Gateway
        {dialect && (
          <span
            style={{
              fontSize: "var(--rei-size-font-sm)",
              fontWeight: 400,
              marginLeft: "var(--rei-space-sm)",
              color: "var(--rei-color-text-muted)",
            }}
          >
            ({dialect})
          </span>
        )}
      </h1>
      <div style={{ minWidth: 320 }}>
        <Select
          value={selectedModel}
          onChange={onModelChange}
          options={models.map((m) => ({
            value: m.id,
            label: `${m.owned_by} / ${m.id}`,
          }))}
          placeholder="Select model..."
        />
      </div>
    </header>
  );
}
