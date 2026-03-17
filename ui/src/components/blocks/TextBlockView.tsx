import type { CSSProperties } from "react";
import type { TextBlock } from "../../api/dialects/types";

type TextBlockViewProps = {
  block: TextBlock;
};

const textStyle: CSSProperties = {
  whiteSpace: "pre-wrap",
  wordBreak: "break-word",
};

const annotationStyle: CSSProperties = {
  fontSize: "var(--rei-size-font-xs, 11px)",
  color: "var(--rei-color-text-muted)",
  marginTop: "var(--rei-space-xs, 4px)",
  display: "flex",
  flexDirection: "column",
  gap: 2,
};

const linkStyle: CSSProperties = {
  color: "var(--rei-color-primary)",
  textDecoration: "none",
};

export function TextBlockView({ block }: TextBlockViewProps) {
  return (
    <div>
      <span style={textStyle}>{block.text}</span>
      {block.annotations && block.annotations.length > 0 && (
        <div style={annotationStyle}>
          {block.annotations.map((a, i) => (
            <a
              key={`${a.url}-${i}`}
              href={a.url}
              target="_blank"
              rel="noopener noreferrer"
              style={linkStyle}
            >
              {a.title ?? a.url}
            </a>
          ))}
        </div>
      )}
    </div>
  );
}
