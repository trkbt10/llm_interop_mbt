import type { CodeExecutionBlock } from "../../api/dialects/types";
import { Code } from "lucide-react";
import { ICON_SIZE } from "../iconSize";
import { BlockLabel } from "./parts/BlockLabel";
import { CodeBlock } from "./parts/CodeBlock";

type CodeExecutionBlockViewProps = {
  block: CodeExecutionBlock;
};

export function CodeExecutionBlockView({ block }: CodeExecutionBlockViewProps) {
  return (
    <div>
      <BlockLabel label={`Code (${block.language})`} icon={<Code size={ICON_SIZE.label} />} />
      <CodeBlock code={block.code} language={block.language} />
    </div>
  );
}
