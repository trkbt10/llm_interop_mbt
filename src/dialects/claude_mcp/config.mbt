///|
/// Configuration for `claude mcp serve` subprocess

///|
pub(all) struct ClaudeMcpConfig {
  command : String // e.g. "claude"
  args : Array[String] // e.g. ["mcp", "serve"]
  env : Map[String, String] // environment variables
  timeout_ms : Int // timeout for tool calls
} derive(Show, Eq, ToJson, FromJson)

///|
pub fn ClaudeMcpConfig::default() -> ClaudeMcpConfig {
  { command: "claude", args: ["mcp", "serve"], env: {}, timeout_ms: 30000 } // 30 seconds
}
