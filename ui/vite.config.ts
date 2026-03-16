import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    port: 19080,
    proxy: {
      "/v1": {
        target: "http://localhost:18080",
        changeOrigin: true,
      },
      "/health": {
        target: "http://localhost:18080",
        changeOrigin: true,
      },
    },
  },
});
