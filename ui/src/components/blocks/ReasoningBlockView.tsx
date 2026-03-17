import { type CSSProperties, useState, useCallback } from "react";
import type { ReasoningBlock } from "../../api/dialects/types";
import { Brain, ChevronDown, ChevronUp } from "lucide-react";
import { ICON_SIZE } from "../iconSize";
import { BlockLabel } from "./parts/BlockLabel";

type ReasoningBlockViewProps = {
  block: ReasoningBlock;
};

const containerStyle: CSSProperties = {
  borderLeft: "2px solid var(--rei-color-border, #e0e0e0)",
  paddingLeft: "var(--rei-space-md, 12px)",
};

const toggleStyle: CSSProperties = {
  cursor: "pointer",
  userSelect: "none",
  background: "none",
  border: "none",
  padding: 0,
};

const textStyle: CSSProperties = {
  whiteSpace: "pre-wrap",
  wordBreak: "break-word",
  fontSize: "var(--rei-size-font-sm, 13px)",
  color: "var(--rei-color-text-muted)",
  marginTop: "var(--rei-space-xs, 4px)",
};

export function ReasoningBlockView({ block }: ReasoningBlockViewProps) {
  const [expanded, setExpanded] = useState(false);

  const toggle = useCallback(() => {
    setExpanded((prev) => !prev);
  }, []);

  return (
    <div style={containerStyle}>
      <button type="button" style={toggleStyle} onClick={toggle}>
        <BlockLabel
          label="Thinking"
          icon={<Brain size={ICON_SIZE.label} />}
        />
        {expanded ? <ChevronUp size={ICON_SIZE.label} /> : <ChevronDown size={ICON_SIZE.label} />}
      </button>
      {expanded && <div style={textStyle}>{block.text}</div>}
    </div>
  );
}
