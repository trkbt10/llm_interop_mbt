/**
 * Result of parsing a data URL (e.g. "data:image/png;base64,iVBOR...").
 */
export type ParsedDataUrl = {
  mimeType: string;
  data: string;
};

/**
 * Parse a data URL and extract its MIME type and base64 data.
 * Returns `null` if the URL is not a valid data URL.
 */
export function parseDataUrl(url: string): ParsedDataUrl | null {
  if (!url.startsWith("data:")) {
    return null;
  }
  const commaIndex = url.indexOf(",");
  if (commaIndex === -1) {
    return null;
  }
  const header = url.slice(0, commaIndex);
  const data = url.slice(commaIndex + 1);
  const mimeTypeMatch = /data:([^;]+)/.exec(header);
  const mimeType = mimeTypeMatch?.[1] ?? "image/png";
  return { mimeType, data };
}

/**
 * Build a base64 data URL from MIME type and data.
 */
export function buildDataUrl(mimeType: string, data: string): string {
  return `data:${mimeType};base64,${data}`;
}
