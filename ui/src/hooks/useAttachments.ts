import { useState, useCallback, useEffect, useRef } from "react";

export type Attachment = {
  file: File;
  previewUrl: string;
};

export function useAttachments() {
  const [attachments, setAttachments] = useState<Attachment[]>([]);
  const attachmentsRef = useRef(attachments);
  attachmentsRef.current = attachments;

  useEffect(() => {
    return () => {
      attachmentsRef.current.forEach((a) => {
        URL.revokeObjectURL(a.previewUrl);
      });
    };
  }, []);

  const add = useCallback((files: File[]) => {
    if (files.length === 0) {
      return;
    }
    const newAttachments = files.map((file) => ({
      file,
      previewUrl: URL.createObjectURL(file),
    }));
    setAttachments((prev) => [...prev, ...newAttachments]);
  }, []);

  const removeAt = useCallback((index: number) => {
    setAttachments((prev) => {
      const removed = prev[index] as Attachment | undefined;
      if (removed) {
        URL.revokeObjectURL(removed.previewUrl);
      }
      return prev.filter((_, i) => i !== index);
    });
  }, []);

  const clear = useCallback(() => {
    setAttachments((prev) => {
      prev.forEach((a) => {
        URL.revokeObjectURL(a.previewUrl);
      });
      return [];
    });
  }, []);

  return {
    attachments,
    add,
    removeAt,
    clear,
  };
}

export function readFileAsBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      resolve(reader.result as string);
    };
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}
