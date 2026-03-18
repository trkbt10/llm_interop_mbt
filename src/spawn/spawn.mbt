///|
/// Shell-safe command builder.
///
/// Assembles a shell command string with proper quoting to prevent injection.
/// Each argument added via `arg()` or `flag()` is wrapped in single quotes.

///|
/// Shell-escape a string by wrapping in single quotes.
/// Embedded single quotes become `'\''` (end quote, literal quote, restart quote).
pub fn shell_quote(s : String) -> String {
  let buf = StringBuilder::new()
  buf.write_string("'")
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i]
    if c == '\'' {
      buf.write_string("'\\''")
    } else {
      buf.write_char(Int::unsafe_to_char(c.to_int()))
    }
  }
  buf.write_string("'")
  buf.to_string()
}

///|
pub(all) struct Command {
  parts : Array[String]
}

///|
/// Create a new command builder. The base command is NOT quoted
/// (it is a trusted literal like "claude" or "codex").
pub fn Command::new(base : String) -> Command {
  { parts: [base] }
}

///|
/// Append a shell-quoted argument.
pub fn Command::arg(self : Command, value : String) -> Command {
  self.parts.push(shell_quote(value))
  self
}

///|
/// Append a flag and its shell-quoted value (e.g. `--tools 'Bash,Read'`).
pub fn Command::flag(self : Command, name : String, value : String) -> Command {
  self.parts.push(name)
  self.parts.push(shell_quote(value))
  self
}

///|
/// Build the final command string.
pub fn Command::to_string(self : Command) -> String {
  self.parts
  .iter()
  .fold(init="", fn(acc, part) {
    if acc == "" {
      part
    } else {
      acc + " " + part
    }
  })
}
