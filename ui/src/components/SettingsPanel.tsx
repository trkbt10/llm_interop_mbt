import { PropertySection } from "react-editor-ui/PropertySection";
import { PropertyRow } from "react-editor-ui/PropertyRow";
import { Select } from "react-editor-ui/Select";
import { Input } from "react-editor-ui/Input";
import type { Model } from "../api/client";
import { getDialect, dialectNames, type DialectName } from "../api/dialects";

export type ChatSettings = {
  maxTokens: string;
  temperature: string;
  topP: string;
  topK: string;
  stop: string;
  systemMessage: string;
};

export const defaultChatSettings: ChatSettings = {
  maxTokens: "",
  temperature: "",
  topP: "",
  topK: "",
  stop: "",
  systemMessage: "",
};

type SettingsPanelProps = {
  models: Model[];
  selectedModel: string;
  onModelChange: (model: string) => void;
  dialect: DialectName;
  onDialectChange: (dialect: DialectName) => void;
  settings: ChatSettings;
  onSettingsChange: (settings: ChatSettings) => void;
};

const dialectOptions = dialectNames.map((d) => ({ value: d, label: d }));

export function SettingsPanel({
  models,
  selectedModel,
  onModelChange,
  dialect,
  onDialectChange,
  settings,
  onSettingsChange,
}: SettingsPanelProps) {
  const update = <K extends keyof ChatSettings>(key: K, value: ChatSettings[K]) => {
    onSettingsChange({ ...settings, [key]: value });
  };

  const { supportedParams } = getDialect(dialect);

  return (
    <div
      style={{
        height: "100%",
        borderRight: "1px solid var(--rei-color-border)",
        display: "flex",
        flexDirection: "column",
      }}
    >
      <div
        style={{
          padding: "var(--rei-space-lg) var(--rei-space-xl)",
          borderBottom: "1px solid var(--rei-color-border)",
          display: "flex",
          flexDirection: "column",
          gap: "var(--rei-space-md)",
          flexShrink: 0,
        }}
      >
        <h1 style={{ margin: 0, fontSize: "var(--rei-size-font-lg)", fontWeight: 600 }}>
          LLM Gateway
        </h1>
        <Select
          value={dialect}
          onChange={(v) => onDialectChange(v as DialectName)}
          options={dialectOptions}
          aria-label="Dialect"
        />
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

      <div style={{ flex: 1, overflowY: "auto" }}>
        <PropertySection title="Parameters" defaultExpanded>
          {supportedParams.maxTokens && (
            <PropertyRow label="Max tokens">
              <Input
                value={settings.maxTokens}
                onChange={(v) => update("maxTokens", v)}
                type="number"
                size="sm"
                aria-label="Max tokens"
              />
            </PropertyRow>
          )}
          {supportedParams.temperature && (
            <PropertyRow label="Temperature">
              <Input
                value={settings.temperature}
                onChange={(v) => update("temperature", v)}
                type="number"
                size="sm"
                aria-label="Temperature"
              />
            </PropertyRow>
          )}
          {supportedParams.topP && (
            <PropertyRow label="Top P">
              <Input
                value={settings.topP}
                onChange={(v) => update("topP", v)}
                type="number"
                size="sm"
                aria-label="Top P"
              />
            </PropertyRow>
          )}
          {supportedParams.topK && (
            <PropertyRow label="Top K">
              <Input
                value={settings.topK}
                onChange={(v) => update("topK", v)}
                type="number"
                size="sm"
                aria-label="Top K"
              />
            </PropertyRow>
          )}
          {supportedParams.stop && (
            <PropertyRow label="Stop sequences">
              <Input
                value={settings.stop}
                onChange={(v) => update("stop", v)}
                size="sm"
                placeholder="comma-separated"
                aria-label="Stop sequences"
              />
            </PropertyRow>
          )}
        </PropertySection>

        <PropertySection title="System message" defaultExpanded>
          <textarea
            value={settings.systemMessage}
            onChange={(e) => update("systemMessage", e.target.value)}
            placeholder="Describe desired model behavior..."
            style={{
              width: "100%",
              minHeight: 120,
              padding: "var(--rei-space-md)",
              border: "1px solid var(--rei-color-border)",
              borderRadius: "var(--rei-radius-md)",
              backgroundColor: "var(--rei-color-surface-raised)",
              color: "inherit",
              fontSize: "var(--rei-size-font-sm)",
              lineHeight: "1.5",
              resize: "vertical",
              outline: "none",
              fontFamily: "inherit",
              boxSizing: "border-box",
            }}
          />
        </PropertySection>
      </div>
    </div>
  );
}
