import type { CSSProperties } from "react";
import type { ToolResultBlock } from "../../api/dialects/types";
import { CheckCircle, XCircle } from "lucide-react";
import { ICON_SIZE } from "../iconSize";
import { BlockContainer } from "./parts/BlockContainer";
import { BlockLabel } from "./parts/BlockLabel";
import { ContentBlockView } from "./ContentBlockView";

type ToolResultBlockViewProps = {
  block: ToolResultBlock;
};

const headerStyle: CSSProperties = {
  display: "flex",
  alignItems: "center",
  gap: "var(--rei-space-sm, 8px)",
  marginBottom: "var(--rei-space-xs, 4px)",
};

const errorStyle: CSSProperties = {
  borderColor: "var(--rei-color-danger, #ef4444)",
};

export function ToolResultBlockView({ block }: ToolResultBlockViewProps) {
  return (
    <BlockContainer style={block.isError ? errorStyle : undefined}>
      <div style={headerStyle}>
        <BlockLabel
          label={block.isError ? "Tool Error" : "Tool Result"}
          icon={block.isError ? <XCircle size={ICON_SIZE.label} /> : <CheckCircle size={ICON_SIZE.label} />}
        />
      </div>
      {block.content.map((inner, i) => (
        <ContentBlockView key={i} block={inner} />
      ))}
    </BlockContainer>
  );
}
