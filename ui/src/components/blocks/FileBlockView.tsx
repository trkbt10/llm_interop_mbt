import type { CSSProperties } from "react";
import type { FileBlock } from "../../api/dialects/types";
import { FileIcon } from "lucide-react";
import { ICON_SIZE } from "../iconSize";
import { BlockContainer } from "./parts/BlockContainer";
import { BlockLabel } from "./parts/BlockLabel";

type FileBlockViewProps = {
  block: FileBlock;
};

const contentStyle: CSSProperties = {
  display: "flex",
  flexDirection: "column",
  gap: "var(--rei-space-xs, 4px)",
};

const detailStyle: CSSProperties = {
  fontSize: "var(--rei-size-font-xs, 11px)",
  color: "var(--rei-color-text-muted)",
};

export function FileBlockView({ block }: FileBlockViewProps) {
  const displayName = block.name ?? block.fileId ?? block.fileUri ?? "file";

  return (
    <BlockContainer>
      <div style={contentStyle}>
        <BlockLabel label="File" icon={<FileIcon size={ICON_SIZE.label} />} />
        <span>{displayName}</span>
        {block.mimeType && <span style={detailStyle}>{block.mimeType}</span>}
      </div>
    </BlockContainer>
  );
}
