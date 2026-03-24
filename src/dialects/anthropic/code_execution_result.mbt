///|
/// Shared normalization for Anthropic code execution result blocks.

///|
priv struct CodeExecutionResultSummary {
  stdout : String
  stderr : String
  return_code : Int
}

///|
fn normalize_code_execution_result(
  content_obj : Json,
) -> CodeExecutionResultSummary {
  // code_execution result blocks may omit stdout/stderr/return_code.
  // Treat missing text fields as empty and infer failure from stderr presence.
  let stdout = match content_obj {
    { "stdout": String(s), .. } => s
    _ => ""
  }
  let stderr = match content_obj {
    { "stderr": String(s), .. } => s
    _ => ""
  }
  let return_code = match content_obj {
    { "return_code": Number(n, ..), .. } => n.to_int()
    _ => if stderr.length() > 0 { 1 } else { 0 }
  }
  { stdout, stderr, return_code }
}

///|
fn CodeExecutionResultSummary::to_response_content_part(
  self : CodeExecutionResultSummary,
) -> @types.ResponseContentPart {
  let outcome = if self.return_code == 0 { "success" } else { "failed" }
  let output = if self.stdout.length() > 0 && self.stderr.length() > 0 {
    "\{self.stdout}\n[stderr]\n\{self.stderr}"
  } else if self.stderr.length() > 0 {
    "[stderr]\n\{self.stderr}"
  } else if self.stdout.length() > 0 {
    self.stdout
  } else {
    "Code execution completed (no output)"
  }
  @types.ResponseContentPart::CodeResult(outcome~, output~)
}

///|
fn CodeExecutionResultSummary::to_output_text(
  self : CodeExecutionResultSummary,
) -> String {
  if self.stdout.length() > 0 && self.stderr.length() > 0 {
    "Code execution output:\n\{self.stdout}\n[stderr]\n\{self.stderr}"
  } else if self.stderr.length() > 0 {
    "Code execution [stderr]:\n\{self.stderr}"
  } else if self.stdout.length() > 0 {
    "Code execution output:\n\{self.stdout}"
  } else {
    "Code execution completed (no output)"
  }
}
