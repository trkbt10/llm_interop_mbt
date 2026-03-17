import type { CSSProperties } from "react";
import type { RefusalBlock } from "../../api/dialects/types";
import { ShieldAlert } from "lucide-react";
import { ICON_SIZE } from "../iconSize";
import { BlockContainer } from "./parts/BlockContainer";
import { BlockLabel } from "./parts/BlockLabel";

type RefusalBlockViewProps = {
  block: RefusalBlock;
};

const containerOverride: CSSProperties = {
  borderColor: "var(--rei-color-warning, #f59e0b)",
  backgroundColor: "var(--rei-color-surface, inherit)",
};

const textStyle: CSSProperties = {
  fontStyle: "italic",
  marginTop: "var(--rei-space-xs, 4px)",
};

export function RefusalBlockView({ block }: RefusalBlockViewProps) {
  return (
    <BlockContainer style={containerOverride}>
      <BlockLabel label="Refused" icon={<ShieldAlert size={ICON_SIZE.label} />} />
      <div style={textStyle}>{block.refusal}</div>
    </BlockContainer>
  );
}
