import type { CSSProperties } from "react";
import type { WebSearchBlock } from "../../api/dialects/types";
import { Search } from "lucide-react";
import { ICON_SIZE } from "../iconSize";
import { BlockContainer } from "./parts/BlockContainer";
import { BlockLabel } from "./parts/BlockLabel";
import { StatusIndicator } from "./parts/StatusIndicator";

type WebSearchBlockViewProps = {
  block: WebSearchBlock;
};

const headerStyle: CSSProperties = {
  display: "flex",
  alignItems: "center",
  justifyContent: "space-between",
};

const queryStyle: CSSProperties = {
  fontStyle: "italic",
  marginTop: "var(--rei-space-xs, 4px)",
};

export function WebSearchBlockView({ block }: WebSearchBlockViewProps) {
  return (
    <BlockContainer>
      <div style={headerStyle}>
        <BlockLabel label="Web Search" icon={<Search size={ICON_SIZE.label} />} />
        <StatusIndicator status={block.status} />
      </div>
      {block.query && <div style={queryStyle}>{block.query}</div>}
    </BlockContainer>
  );
}
