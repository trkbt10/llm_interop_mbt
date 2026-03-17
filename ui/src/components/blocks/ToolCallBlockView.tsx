import type { CSSProperties } from "react";
import type { ToolCallBlock } from "../../api/dialects/types";
import { Wrench } from "lucide-react";
import { ICON_SIZE } from "../iconSize";
import { BlockContainer } from "./parts/BlockContainer";
import { BlockLabel } from "./parts/BlockLabel";
import { CodeBlock } from "./parts/CodeBlock";

type ToolCallBlockViewProps = {
  block: ToolCallBlock;
};

const headerStyle: CSSProperties = {
  display: "flex",
  alignItems: "center",
  justifyContent: "space-between",
  marginBottom: "var(--rei-space-xs, 4px)",
};

const nameStyle: CSSProperties = {
  fontFamily: "monospace",
  fontSize: "var(--rei-size-font-sm, 13px)",
  fontWeight: 600,
};

function formatArguments(args: string): string {
  try {
    return JSON.stringify(JSON.parse(args), null, 2);
  } catch {
    return args;
  }
}

export function ToolCallBlockView({ block }: ToolCallBlockViewProps) {
  return (
    <BlockContainer>
      <div style={headerStyle}>
        <BlockLabel label="Tool Call" icon={<Wrench size={ICON_SIZE.label} />} />
        <span style={nameStyle}>{block.name}</span>
      </div>
      <CodeBlock code={formatArguments(block.arguments)} language="json" />
    </BlockContainer>
  );
}
