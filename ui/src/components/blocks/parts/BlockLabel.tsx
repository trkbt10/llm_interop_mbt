import type { CSSProperties, ReactNode } from "react";

type BlockLabelProps = {
  label: string;
  icon?: ReactNode;
  style?: CSSProperties;
};

const baseStyle: CSSProperties = {
  display: "inline-flex",
  alignItems: "center",
  gap: "var(--rei-space-xs, 4px)",
  fontSize: "var(--rei-size-font-xs, 11px)",
  fontWeight: 600,
  textTransform: "uppercase",
  letterSpacing: "0.05em",
  color: "var(--rei-color-text-muted)",
};

export function BlockLabel({ label, icon, style }: BlockLabelProps) {
  return (
    <span style={{ ...baseStyle, ...style }}>
      {icon}
      {label}
    </span>
  );
}
