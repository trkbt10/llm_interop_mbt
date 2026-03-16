import { BrowserRouter, Routes, Route } from "react-router";
import { IndexPage } from "./routes/index";

export function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<IndexPage />} />
      </Routes>
    </BrowserRouter>
  );
}
