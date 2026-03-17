import type { ResponseContentBlock } from "../../api/dialects/types";
import { TextBlockView } from "./TextBlockView";
import { ImageBlockView } from "./ImageBlockView";
import { AudioBlockView } from "./AudioBlockView";
import { FileBlockView } from "./FileBlockView";
import { ToolCallBlockView } from "./ToolCallBlockView";
import { ToolResultBlockView } from "./ToolResultBlockView";
import { WebSearchBlockView } from "./WebSearchBlockView";
import { CodeExecutionBlockView } from "./CodeExecutionBlockView";
import { CodeExecutionResultBlockView } from "./CodeExecutionResultBlockView";
import { ReasoningBlockView } from "./ReasoningBlockView";
import { RefusalBlockView } from "./RefusalBlockView";

type ContentBlockViewProps = {
  block: ResponseContentBlock;
};

export function ContentBlockView({ block }: ContentBlockViewProps) {
  switch (block.type) {
    case "text":
      return <TextBlockView block={block} />;
    case "image":
      return <ImageBlockView block={block} />;
    case "audio":
      return <AudioBlockView block={block} />;
    case "file":
      return <FileBlockView block={block} />;
    case "tool_call":
      return <ToolCallBlockView block={block} />;
    case "tool_result":
      return <ToolResultBlockView block={block} />;
    case "web_search":
      return <WebSearchBlockView block={block} />;
    case "code_execution":
      return <CodeExecutionBlockView block={block} />;
    case "code_execution_result":
      return <CodeExecutionResultBlockView block={block} />;
    case "reasoning":
      return <ReasoningBlockView block={block} />;
    case "refusal":
      return <RefusalBlockView block={block} />;
    default:
      return null;
  }
}
