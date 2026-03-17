import { useMemo } from "react";
import type { AudioBlock } from "../../api/dialects/types";
import { buildDataUrl } from "../../utils/dataUrl";

type AudioBlockViewProps = {
  block: AudioBlock;
};

export function AudioBlockView({ block }: AudioBlockViewProps) {
  const src = useMemo(
    () => buildDataUrl(block.mimeType ?? "audio/mp3", block.data),
    [block.mimeType, block.data]
  );

  return (
    <audio controls preload="metadata" style={{ maxWidth: 400, width: "100%" }}>
      <source src={src} />
    </audio>
  );
}
