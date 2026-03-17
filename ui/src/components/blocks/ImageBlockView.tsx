import { type CSSProperties, useMemo } from "react";
import type { ImageBlock } from "../../api/dialects/types";
import { buildDataUrl } from "../../utils/dataUrl";

type ImageBlockViewProps = {
  block: ImageBlock;
};

const imgStyle: CSSProperties = {
  maxWidth: "100%",
  maxHeight: 400,
  borderRadius: "var(--rei-radius-md, 8px)",
  objectFit: "contain",
};

export function ImageBlockView({ block }: ImageBlockViewProps) {
  const src = useMemo(() => {
    if (block.url) {
      return block.url;
    }
    if (block.data) {
      return buildDataUrl(block.mimeType ?? "image/png", block.data);
    }
    return "";
  }, [block.url, block.data, block.mimeType]);

  if (!src) {
    return null;
  }

  return <img src={src} alt="" loading="lazy" style={imgStyle} />;
}
