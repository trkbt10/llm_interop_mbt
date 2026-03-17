import type {
  ContentPartRendererProps,
  CustomContentPart,
} from "react-editor-ui/chat/ChatMessageDisplay";
import type { ResponseContentBlock } from "../../api/dialects/types";
import { ContentBlockView } from "./ContentBlockView";

/**
 * Renders a custom content part whose `data` is a single ResponseContentBlock.
 * The `contentType` matches the block's `type` field (e.g. "tool_call", "reasoning").
 *
 * Native content types (text, image, audio, file) are handled by
 * react-editor-ui's built-in renderers and never reach this component.
 */
export function CustomContentPartRenderer({
  part,
}: ContentPartRendererProps<CustomContentPart>) {
  const block = part.data as ResponseContentBlock;

  return <ContentBlockView block={block} />;
}
