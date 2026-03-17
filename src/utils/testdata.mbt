///|
/// Resolve a testdata path by searching from CWD upward for moon.mod.json.
/// This handles the case where `moon test` runs from a subdirectory (e.g. ui/).
pub fn resolve_testdata_path(relative_path : String) -> String {
  // Try the path as-is first (CWD is project root)
  let candidates = [
    relative_path,
    "../" + relative_path,
    "../../" + relative_path,
  ]
  for candidate in candidates {
    if file_readable(candidate) {
      return candidate
    }
  }
  // Fallback: return as-is (will produce a clear error)
  relative_path
}

///|
fn file_readable(path : String) -> Bool {
  try {
    let _ = @fs.read_file_to_string(path)
    true
  } catch {
    _ => false
  }
}

///|
/// Read a testdata file, searching upward from CWD for the project root.
pub fn read_testdata(relative_path : String) -> String raise {
  @fs.read_file_to_string(resolve_testdata_path(relative_path))
}
