// @vitest-environment jsdom
import { describe, it, expect, vi, beforeEach } from "vitest";
import { renderHook, act } from "@testing-library/react";
import { useAttachments } from "./useAttachments";

// Track createObjectURL / revokeObjectURL calls
let urlCounter = 0;
const createdUrls = new Set<string>();
const revokedUrls = new Set<string>();

beforeEach(() => {
  urlCounter = 0;
  createdUrls.clear();
  revokedUrls.clear();

  vi.stubGlobal(
    "URL",
    new Proxy(globalThis.URL, {
      get(target, prop) {
        if (prop === "createObjectURL") {
          return () => {
            const url = `blob:test/${urlCounter++}`;
            createdUrls.add(url);
            return url;
          };
        }
        if (prop === "revokeObjectURL") {
          return (url: string) => {
            revokedUrls.add(url);
          };
        }
        return Reflect.get(target, prop) as unknown;
      },
    })
  );
});

function makeFile(name: string) {
  return new File(["content"], name, { type: "text/plain" });
}

describe("useAttachments", () => {
  it("add creates object URLs for files", () => {
    const { result } = renderHook(() => useAttachments());

    act(() => {
      result.current.add([makeFile("a.txt"), makeFile("b.txt")]);
    });

    expect(result.current.attachments).toHaveLength(2);
    expect(createdUrls.size).toBe(2);
    result.current.attachments.forEach((a) => {
      expect(createdUrls.has(a.previewUrl)).toBe(true);
    });
  });

  it("removeAt revokes the removed attachment's URL", () => {
    const { result } = renderHook(() => useAttachments());

    act(() => {
      result.current.add([makeFile("a.txt"), makeFile("b.txt")]);
    });

    const removedUrl = result.current.attachments[0].previewUrl;

    act(() => {
      result.current.removeAt(0);
    });

    expect(result.current.attachments).toHaveLength(1);
    expect(revokedUrls.has(removedUrl)).toBe(true);
  });

  it("clear revokes all URLs", () => {
    const { result } = renderHook(() => useAttachments());

    act(() => {
      result.current.add([makeFile("a.txt"), makeFile("b.txt")]);
    });

    const urls = result.current.attachments.map((a) => a.previewUrl);

    act(() => {
      result.current.clear();
    });

    expect(result.current.attachments).toHaveLength(0);
    urls.forEach((url) => {
      expect(revokedUrls.has(url)).toBe(true);
    });
  });

  it("BUG: adding files should not revoke existing URLs", () => {
    const { result } = renderHook(() => useAttachments());

    act(() => {
      result.current.add([makeFile("a.txt")]);
    });

    const firstUrl = result.current.attachments[0].previewUrl;
    revokedUrls.clear(); // reset to isolate the next action

    act(() => {
      result.current.add([makeFile("b.txt")]);
    });

    // The first URL should NOT have been revoked — it's still in use
    expect(revokedUrls.has(firstUrl)).toBe(false);
    expect(result.current.attachments).toHaveLength(2);
  });

  it("unmount revokes all remaining URLs", () => {
    const { result, unmount } = renderHook(() => useAttachments());

    act(() => {
      result.current.add([makeFile("a.txt"), makeFile("b.txt")]);
    });

    const urls = result.current.attachments.map((a) => a.previewUrl);
    revokedUrls.clear(); // isolate: only unmount should trigger revokes

    unmount();

    urls.forEach((url) => {
      expect(revokedUrls.has(url)).toBe(true);
    });
  });
});
