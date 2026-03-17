import type { CSSProperties } from "react";
import type { CodeExecutionResultBlock } from "../../api/dialects/types";
import { Terminal } from "lucide-react";
import { ICON_SIZE } from "../iconSize";
import { BlockContainer } from "./parts/BlockContainer";
import { BlockLabel } from "./parts/BlockLabel";
import { StatusIndicator } from "./parts/StatusIndicator";

type CodeExecutionResultBlockViewProps = {
  block: CodeExecutionResultBlock;
};

const headerStyle: CSSProperties = {
  display: "flex",
  alignItems: "center",
  justifyContent: "space-between",
  marginBottom: "var(--rei-space-xs, 4px)",
};

const outputStyle: CSSProperties = {
  fontFamily: "monospace",
  fontSize: "var(--rei-size-font-xs, 11px)",
  whiteSpace: "pre-wrap",
  wordBreak: "break-word",
};

export function CodeExecutionResultBlockView({ block }: CodeExecutionResultBlockViewProps) {
  return (
    <BlockContainer>
      <div style={headerStyle}>
        <BlockLabel label="Output" icon={<Terminal size={ICON_SIZE.label} />} />
        {block.outcome && <StatusIndicator status={block.outcome} />}
      </div>
      <div style={outputStyle}>{block.output}</div>
    </BlockContainer>
  );
}
