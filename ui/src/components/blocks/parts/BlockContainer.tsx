import type { CSSProperties, ReactNode } from "react";

type BlockContainerProps = {
  children: ReactNode;
  style?: CSSProperties;
};

const baseStyle: CSSProperties = {
  padding: "var(--rei-space-sm, 8px) var(--rei-space-md, 12px)",
  borderRadius: "var(--rei-radius-md, 8px)",
  backgroundColor: "var(--rei-color-surface-raised, #f5f5f5)",
  border: "1px solid var(--rei-color-border, #e0e0e0)",
  fontSize: "var(--rei-size-font-sm, 13px)",
  lineHeight: 1.5,
};

export function BlockContainer({ children, style }: BlockContainerProps) {
  return <div style={{ ...baseStyle, ...style }}>{children}</div>;
}
