/**
 * @vitest-environment jsdom
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render } from "@testing-library/react";
import { ConstrainedImageRenderer } from "./ConstrainedImageRenderer";
import type { ChatMessage } from "react-editor-ui/chat/ChatMessageDisplay";

const stubMessage: ChatMessage = {
  id: "msg-1",
  role: "user",
  content: "test",
};

// ---------------------------------------------------------------------------
// ResizeObserver mock
// ---------------------------------------------------------------------------

type ResizeCallback = (entries: { contentRect: { height: number } }[]) => void;

let resizeCallbacks: ResizeCallback[] = [];
let observedElements: Element[] = [];

class MockResizeObserver {
  private cb: ResizeCallback;

  constructor(cb: ResizeCallback) {
    this.cb = cb;
    resizeCallbacks.push(cb);
  }

  observe(el: Element) {
    observedElements.push(el);
  }

  disconnect() {
    resizeCallbacks = resizeCallbacks.filter((c) => c !== this.cb);
  }

  unobserve() {
    // no-op
  }
}

function simulateResize(height: number) {
  for (const cb of resizeCallbacks) {
    cb([{ contentRect: { height } }]);
  }
}

// ---------------------------------------------------------------------------
// Scroll parent mock
// ---------------------------------------------------------------------------

const originalGetComputedStyle = window.getComputedStyle;

function setupScrollParent(container: HTMLElement): { getScrollTopSets: () => number[] } {
  const scrollTopSets: number[] = [];
  let currentScrollTop = 100;

  window.getComputedStyle = vi.fn().mockReturnValue({
    overflow: "auto",
    overflowY: "auto",
  });

  const parent = container.firstElementChild?.parentElement;
  if (parent) {
    Object.defineProperty(parent, "scrollTop", {
      get: () => currentScrollTop,
      set: (v: number) => {
        currentScrollTop = v;
        scrollTopSets.push(v);
      },
      configurable: true,
    });
  }

  return { getScrollTopSets: () => scrollTopSets };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

beforeEach(() => {
  resizeCallbacks = [];
  observedElements = [];
  vi.stubGlobal("ResizeObserver", MockResizeObserver);
});

afterEach(() => {
  window.getComputedStyle = originalGetComputedStyle;
  vi.restoreAllMocks();
});

describe("ConstrainedImageRenderer", () => {
  it("renders an img with correct src and eager loading", () => {
    const { container } = render(
      <ConstrainedImageRenderer
        part={{ type: "image", url: "https://example.com/img.png" }}
        message={stubMessage}
      />,
    );

    const img = container.querySelector("img");
    expect(img).not.toBeNull();
    expect(img?.getAttribute("src")).toBe("https://example.com/img.png");
    expect(img?.getAttribute("loading")).toBe("eager");
  });

  it("applies maxWidth, maxHeight, and minHeight constraints", () => {
    const { container } = render(
      <ConstrainedImageRenderer
        part={{ type: "image", url: "https://example.com/img.png" }}
        message={stubMessage}
      />,
    );

    const img = container.querySelector("img");
    expect(img?.style.maxWidth).toBe("100%");
    expect(img?.style.maxHeight).toBe("400px");
    expect(img?.style.minHeight).toBe("100px");
  });

  it("observes the container with ResizeObserver", () => {
    const { container } = render(
      <ConstrainedImageRenderer
        part={{ type: "image", url: "https://example.com/img.png" }}
        message={stubMessage}
      />,
    );

    expect(observedElements).toHaveLength(1);
    expect(observedElements[0]).toBe(container.firstElementChild);
  });

  it("nudges scroller when height changes", () => {
    const { container } = render(
      <ConstrainedImageRenderer
        part={{ type: "image", url: "https://example.com/img.png" }}
        message={stubMessage}
      />,
    );

    const { getScrollTopSets } = setupScrollParent(container);

    // Height changes from 0 → 350
    simulateResize(350);
    expect(getScrollTopSets()).toContain(101); // scrollTop + 1
  });

  it("does NOT nudge when height is unchanged (loop prevention)", () => {
    const { container } = render(
      <ConstrainedImageRenderer
        part={{ type: "image", url: "https://example.com/img.png" }}
        message={stubMessage}
      />,
    );

    const { getScrollTopSets } = setupScrollParent(container);

    // First resize → nudge
    simulateResize(350);
    const countAfterFirst = getScrollTopSets().length;

    // Same height again → should NOT nudge
    simulateResize(350);
    expect(getScrollTopSets()).toHaveLength(countAfterFirst);

    // Slightly different but within epsilon → should NOT nudge
    simulateResize(350.5);
    expect(getScrollTopSets()).toHaveLength(countAfterFirst);
  });

  it("nudges again when height changes meaningfully (e.g. window resize)", () => {
    const { container } = render(
      <ConstrainedImageRenderer
        part={{ type: "image", url: "https://example.com/img.png" }}
        message={stubMessage}
      />,
    );

    const { getScrollTopSets } = setupScrollParent(container);

    simulateResize(350);
    const countAfterFirst = getScrollTopSets().length;

    // Meaningful resize → should nudge again
    simulateResize(200);
    expect(getScrollTopSets().length).toBeGreaterThan(countAfterFirst);
  });

  it("terminates: resize→nudge→re-measure→same height→stop", () => {
    const { container } = render(
      <ConstrainedImageRenderer
        part={{ type: "image", url: "https://example.com/img.png" }}
        message={stubMessage}
      />,
    );

    const { getScrollTopSets } = setupScrollParent(container);

    // Simulate the exact cycle the virtual scroller would cause:
    // 1. Image loads → height 350 → nudge
    simulateResize(350);
    const nudgeCount1 = getScrollTopSets().length;

    // 2. Virtual scroller re-renders → ResizeObserver fires with same 350 → no nudge
    simulateResize(350);
    expect(getScrollTopSets()).toHaveLength(nudgeCount1);

    // 3. Fire it 100 more times at same height — must never nudge
    for (let i = 0; i < 100; i++) {
      simulateResize(350);
    }
    expect(getScrollTopSets()).toHaveLength(nudgeCount1);
  });

  it("disconnects ResizeObserver on unmount", () => {
    const { unmount } = render(
      <ConstrainedImageRenderer
        part={{ type: "image", url: "https://example.com/img.png" }}
        message={stubMessage}
      />,
    );

    expect(resizeCallbacks).toHaveLength(1);
    unmount();
    expect(resizeCallbacks).toHaveLength(0);
  });
});
