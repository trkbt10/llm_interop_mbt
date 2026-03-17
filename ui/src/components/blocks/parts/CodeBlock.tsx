import { type CSSProperties, useCallback, useState } from "react";
import { Copy, Check } from "lucide-react";
import { ICON_SIZE } from "../../iconSize";

type CodeBlockProps = {
  code: string;
  language?: string;
};

const preStyle: CSSProperties = {
  margin: 0,
  padding: "var(--rei-space-sm, 8px) var(--rei-space-md, 12px)",
  borderRadius: "var(--rei-radius-md, 8px)",
  backgroundColor: "var(--rei-color-surface-raised, #f5f5f5)",
  border: "1px solid var(--rei-color-border, #e0e0e0)",
  fontSize: "var(--rei-size-font-xs, 11px)",
  fontFamily: "monospace",
  whiteSpace: "pre-wrap",
  wordBreak: "break-word",
  overflow: "auto",
  maxHeight: 300,
  position: "relative" as const,
};

const copyButtonStyle: CSSProperties = {
  position: "absolute",
  top: "var(--rei-space-xs, 4px)",
  right: "var(--rei-space-xs, 4px)",
  display: "inline-flex",
  alignItems: "center",
  gap: 4,
  padding: "2px 6px",
  fontSize: "var(--rei-size-font-xs, 11px)",
  background: "var(--rei-color-surface-overlay, rgba(0,0,0,0.05))",
  border: "1px solid var(--rei-color-border, #e0e0e0)",
  borderRadius: "var(--rei-radius-sm, 4px)",
  cursor: "pointer",
  color: "var(--rei-color-text-muted)",
};

export function CodeBlock({ code, language }: CodeBlockProps) {
  const [copied, setCopied] = useState(false);

  const handleCopy = useCallback(() => {
    void navigator.clipboard.writeText(code).then(() => {
      setCopied(true);
      setTimeout(() => setCopied(false), 1500);
    });
  }, [code]);

  return (
    <pre style={preStyle} data-language={language}>
      <button type="button" style={copyButtonStyle} onClick={handleCopy}>
        {copied ? <Check size={ICON_SIZE.label} /> : <Copy size={ICON_SIZE.label} />}
      </button>
      <code>{code}</code>
    </pre>
  );
}
