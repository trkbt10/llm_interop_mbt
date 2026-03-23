///|
/// Shared tool_choice conversion helpers for Anthropic request builders.

///|
fn convert_tool_choice_to_anthropic(tool_choice : Json) -> Json? {
  match tool_choice {
    String("auto") => Some({ "type": "auto" })
    String("none") => None
    String("required") => Some({ "type": "any" })
    { "type": String("function"), "function": { "name": String(name), .. }, .. } =>
      Some({ "type": "tool", "name": name })
    { "type": String("function"), "name": String(name), .. } =>
      Some({ "type": "tool", "name": name })
    _ => None
  }
}
