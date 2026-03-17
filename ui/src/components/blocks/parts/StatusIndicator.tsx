import type { CSSProperties } from "react";

type StatusIndicatorProps = {
  status: string;
};

const dotColors: Record<string, string> = {
  completed: "var(--rei-color-success, #22c55e)",
  searching: "var(--rei-color-warning, #f59e0b)",
  in_progress: "var(--rei-color-warning, #f59e0b)",
  error: "var(--rei-color-danger, #ef4444)",
};

const containerStyle: CSSProperties = {
  display: "inline-flex",
  alignItems: "center",
  gap: "var(--rei-space-xs, 4px)",
  fontSize: "var(--rei-size-font-xs, 11px)",
  color: "var(--rei-color-text-muted)",
};

export function StatusIndicator({ status }: StatusIndicatorProps) {
  const color = dotColors[status] ?? "var(--rei-color-text-muted)";

  return (
    <span style={containerStyle}>
      <span
        style={{
          display: "inline-block",
          width: 6,
          height: 6,
          borderRadius: "50%",
          backgroundColor: color,
        }}
      />
      {status}
    </span>
  );
}
