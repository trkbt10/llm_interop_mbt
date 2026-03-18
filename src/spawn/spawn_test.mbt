///|
test "shell_quote: simple string" {
  assert_eq(shell_quote("hello"), "'hello'")
}

///|
test "shell_quote: string with single quote" {
  assert_eq(shell_quote("it's"), "'it'\\''s'")
}

///|
test "shell_quote: string with spaces" {
  assert_eq(shell_quote("hello world"), "'hello world'")
}

///|
test "shell_quote: string with semicolon (injection attempt)" {
  assert_eq(shell_quote("foo;rm -rf /"), "'foo;rm -rf /'")
}

///|
test "shell_quote: string with backticks" {
  assert_eq(shell_quote("$(whoami)"), "'$(whoami)'")
}

///|
test "shell_quote: empty string" {
  assert_eq(shell_quote(""), "''")
}

///|
test "Command::new basic" {
  let cmd = Command::new("claude").arg("mcp").arg("serve")
  assert_eq(cmd.to_string(), "claude 'mcp' 'serve'")
}

///|
test "Command with flag" {
  let cmd = Command::new("claude")
    .arg("mcp")
    .arg("serve")
    .flag("--tools", "Bash,Read,Edit")
  assert_eq(cmd.to_string(), "claude 'mcp' 'serve' --tools 'Bash,Read,Edit'")
}

///|
test "Command: injection in arg is neutralized" {
  let cmd = Command::new("claude").arg("mcp; rm -rf /")
  assert_eq(cmd.to_string(), "claude 'mcp; rm -rf /'")
}

///|
test "Command: injection in flag value is neutralized" {
  let cmd = Command::new("cmd").flag("--name", "'; DROP TABLE users; --")
  assert_eq(cmd.to_string(), "cmd --name ''\\''; DROP TABLE users; --'")
}
