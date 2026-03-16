import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { injectTheme } from "react-editor-ui/themes";
import { App } from "./App";
import "./index.css";

// Apply light theme (respect system preference)
const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
injectTheme(prefersDark ? "dark" : "light");

const rootElement = document.getElementById("root");
if (!rootElement) {
  throw new Error("Root element not found");
}
createRoot(rootElement).render(
  <StrictMode>
    <App />
  </StrictMode>
);
