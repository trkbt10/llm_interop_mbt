import { memo, useEffect, useMemo, useRef } from "react";
import type { CSSProperties } from "react";
import type {
  ContentPartRendererProps,
  ImageContentPart,
} from "react-editor-ui/chat/ChatMessageDisplay";

const containerStyle: CSSProperties = {
  maxWidth: "100%",
  overflow: "hidden",
  borderRadius: "var(--rei-radius-md, 8px)",
  marginTop: "var(--rei-space-xs, 4px)",
};

const imgBaseStyle: CSSProperties = {
  display: "block",
  maxWidth: "100%",
  maxHeight: 400,
  minHeight: 100,
  borderRadius: "var(--rei-radius-md, 8px)",
  objectFit: "contain",
};

/** Height difference threshold to consider "changed" (px). */
const HEIGHT_EPSILON = 1;

/**
 * Find the nearest scrollable ancestor.
 */
function findScrollParent(el: HTMLElement | null): HTMLElement | null {
  let current = el?.parentElement ?? null;
  while (current) {
    const style = getComputedStyle(current);
    if (/auto|scroll/.test(style.overflow) || /auto|scroll/.test(style.overflowY)) {
      return current;
    }
    current = current.parentElement;
  }
  return null;
}

/**
 * Nudge the nearest scroll container's scrollTop by ±1px so
 * the virtual scroller's onScroll fires and triggers re-measurement.
 */
function nudgeScroller(el: HTMLElement | null): void {
  const scroller = findScrollParent(el);
  if (!scroller) {
    return;
  }
  const prev = scroller.scrollTop;
  scroller.scrollTop = prev + 1;
  requestAnimationFrame(() => {
    scroller.scrollTop = prev;
  });
}

/**
 * Image content renderer that constrains images within their parent bubble.
 *
 * Uses ResizeObserver on the container to detect height changes (image load,
 * window resize, etc.) and nudges the virtual scroller to re-measure.
 *
 * Loop prevention: tracks the last height that triggered a nudge. A new
 * nudge only fires when the observed height differs by more than
 * HEIGHT_EPSILON px from the last-nudged height. After the virtual scroller
 * re-renders at the correct height, the next observation sees the same
 * height and the cycle terminates.
 */
export const ConstrainedImageRenderer = memo(function ConstrainedImageRenderer({
  part,
}: ContentPartRendererProps<ImageContentPart>) {
  const containerRef = useRef<HTMLDivElement>(null);
  const lastNudgedHeightRef = useRef(0);

  const imgStyle = useMemo<CSSProperties>(
    () => ({
      ...imgBaseStyle,
      width: part.width,
      height: part.height,
    }),
    [part.width, part.height],
  );

  useEffect(() => {
    const el = containerRef.current;
    if (!el) {
      return;
    }

    const observer = new ResizeObserver((entries) => {
      for (const entry of entries) {
        const newHeight = entry.contentRect.height;
        if (Math.abs(newHeight - lastNudgedHeightRef.current) > HEIGHT_EPSILON) {
          lastNudgedHeightRef.current = newHeight;
          nudgeScroller(el);
        }
      }
    });

    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  return (
    <div ref={containerRef} style={containerStyle}>
      <img
        src={part.url}
        alt={part.alt ?? ""}
        style={imgStyle}
        loading="eager"
      />
    </div>
  );
});
