# `claude mcp serve` — MCP Tools Reference

Captured from Claude Code v2.1.78 (`claude mcp serve` → `tools/list`).

Total: **23 tools**

---

## Agent

> delegate work to a subagent

Aliases: `Task`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `description` | string | Yes | A short (3-5 word) description of the task |
| `prompt` | string | Yes | The task for the agent to perform |
| `subagent_type` | string |  | The type of specialized agent to use for this task |
| `model` | string |  | Optional model override for this agent. Takes precedence over the agent definition's model frontmatter. If omitted, u... |
| `run_in_background` | boolean |  | Set to true to run this agent in the background. You will be notified when it completes. |
| `name` | string |  | Name for the spawned agent. Makes it addressable via SendMessage({to: name}) while running. |
| `team_name` | string |  | Team name for spawning. Uses current team context if omitted. |
| `mode` | string |  | Permission mode for spawned teammate (e.g., "plan" to require plan approval). |
| `isolation` | string |  | Isolation mode. "worktree" creates a temporary git worktree so the agent works on an isolated copy of the repo. |

`model` values: `sonnet`, `opus`, `haiku`

`mode` values: `acceptEdits`, `bypassPermissions`, `default`, `dontAsk`, `plan`, `auto`

`isolation` values: `worktree`

---

## TaskOutput

> read output/logs from a background task

Aliases: `AgentOutputTool`, `BashOutputTool`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `task_id` | string | Yes | The task ID to get output from |
| `block` | boolean | Yes | Whether to wait for completion |
| `timeout` | number | Yes | Max wait time in ms |

---

## Bash

> execute shell commands

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `command` | string | Yes | The command to execute |
| `timeout` | number |  | Optional timeout in milliseconds (max 600000) |
| `description` | string |  | Clear, concise description of what this command does in active voice. Never use words like "complex" or "risk" in the... |
| `run_in_background` | boolean |  | Set to true to run this command in the background. Use TaskOutput to read the output later. |
| `dangerouslyDisableSandbox` | boolean |  | Set this to true to dangerously override sandbox mode and run commands without sandboxing. |

---

## Glob

> find files by name pattern or wildcard

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `pattern` | string | Yes | The glob pattern to match files against |
| `path` | string |  | The directory to search in. If not specified, the current working directory will be used. IMPORTANT: Omit this field ... |

---

## Grep

> search file contents with regex (ripgrep)

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `pattern` | string | Yes | The regular expression pattern to search for in file contents |
| `path` | string |  | File or directory to search in (rg PATH). Defaults to current working directory. |
| `glob` | string |  | Glob pattern to filter files (e.g. "*.js", "*.{ts,tsx}") - maps to rg --glob |
| `output_mode` | string |  | Output mode: "content" shows matching lines (supports -A/-B/-C context, -n line numbers, head_limit), "files_with_mat... |
| `-B` | number |  | Number of lines to show before each match (rg -B). Requires output_mode: "content", ignored otherwise. |
| `-A` | number |  | Number of lines to show after each match (rg -A). Requires output_mode: "content", ignored otherwise. |
| `-C` | number |  | Alias for context. |
| `context` | number |  | Number of lines to show before and after each match (rg -C). Requires output_mode: "content", ignored otherwise. |
| `-n` | boolean |  | Show line numbers in output (rg -n). Requires output_mode: "content", ignored otherwise. Defaults to true. |
| `-i` | boolean |  | Case insensitive search (rg -i) |
| `type` | string |  | File type to search (rg --type). Common types: js, py, rust, go, java, etc. More efficient than include for standard ... |
| `head_limit` | number |  | Limit output to first N lines/entries, equivalent to "\| head -N". Works across all output modes: content (limits out... |
| `offset` | number |  | Skip first N lines/entries before applying head_limit, equivalent to "\| tail -n +N \| head -N". Works across all out... |
| `multiline` | boolean |  | Enable multiline mode where . matches newlines and patterns can span lines (rg -U --multiline-dotall). Default: false. |

`output_mode` values: `content`, `files_with_matches`, `count`

---

## ExitPlanMode

> present plan for approval and start coding (plan mode only)

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `allowedPrompts` | array |  | Prompt-based permissions needed to implement the plan. These describe categories of actions rather than specific comm... |

---

## Read

> read files, images, PDFs, notebooks

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `file_path` | string | Yes | The absolute path to the file to read |
| `offset` | number |  | The line number to start reading from. Only provide if the file is too large to read at once |
| `limit` | number |  | The number of lines to read. Only provide if the file is too large to read at once. |
| `pages` | string |  | Page range for PDF files (e.g., "1-5", "3", "10-20"). Only applicable to PDF files. Maximum 20 pages per request. |

---

## Edit

> modify file contents in place

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `file_path` | string | Yes | The absolute path to the file to modify |
| `old_string` | string | Yes | The text to replace |
| `new_string` | string | Yes | The text to replace it with (must be different from old_string) |
| `replace_all` | boolean |  | Replace all occurrences of old_string (default false) |

---

## Write

> create or overwrite files

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `file_path` | string | Yes | The absolute path to the file to write (must be absolute, not relative) |
| `content` | string | Yes | The content to write to the file |

---

## NotebookEdit

> edit Jupyter notebook cells (.ipynb)

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `notebook_path` | string | Yes | The absolute path to the Jupyter notebook file to edit (must be absolute, not relative) |
| `cell_id` | string |  | The ID of the cell to edit. When inserting a new cell, the new cell will be inserted after the cell with this ID, or ... |
| `new_source` | string | Yes | The new source for the cell |
| `cell_type` | string |  | The type of the cell (code or markdown). If not specified, it defaults to the current cell type. If using edit_mode=i... |
| `edit_mode` | string |  | The type of edit to make (replace, insert, delete). Defaults to replace. |

`cell_type` values: `code`, `markdown`

`edit_mode` values: `replace`, `insert`, `delete`

---

## WebFetch

> fetch and extract content from a URL

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `url` | string | Yes | The URL to fetch content from |
| `prompt` | string | Yes | The prompt to run on the fetched content |

---

## TodoWrite

> manage the session task checklist

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `todos` | array | Yes | The updated todo list |

---

## WebSearch

> search the web for current information

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `query` | string | Yes | The search query to use |
| `allowed_domains` | array |  | Only include search results from these domains |
| `blocked_domains` | array |  | Never include search results from these domains |

---

## TaskStop

> kill a running background task

Aliases: `KillShell`

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `task_id` | string |  | The ID of the background task to stop |
| `shell_id` | string |  | Deprecated: use task_id instead |

---

## AskUserQuestion

> prompt the user with a multiple-choice question

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `questions` | array | Yes | Questions to ask the user (1-4 questions) |
| `answers` | object |  | User answers collected by the permission component |
| `annotations` | object |  | Optional per-question annotations from the user (e.g., notes on preview selections). Keyed by question text. |
| `metadata` | object |  | Optional metadata for tracking and analytics purposes. Not displayed to user. |

---

## Skill

> invoke a slash-command skill

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `skill` | string | Yes | The skill name. E.g., "commit", "review-pr", or "pdf" |
| `args` | string |  | Optional arguments for the skill |

---

## EnterPlanMode

> switch to plan mode to design an approach before coding

---

## EnterWorktree

> create an isolated git worktree and switch into it

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `name` | string |  | Optional name for the worktree. A random name is generated if not provided. |

---

## ExitWorktree

> exit a worktree session and return to the original directory

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `action` | string | Yes | "keep" leaves the worktree and branch on disk; "remove" deletes both. |
| `discard_changes` | boolean |  | Required true when action is "remove" and the worktree has uncommitted files or unmerged commits. The tool will refus... |

`action` values: `keep`, `remove`

---

## CronCreate

> schedule a recurring prompt for this session

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `cron` | string | Yes | Standard 5-field cron expression in local time: "M H DoM Mon DoW" (e.g. "*/5 * * * *" = every 5 minutes, "30 14 28 2 ... |
| `prompt` | string | Yes | The prompt to enqueue at each fire time. |
| `recurring` | boolean |  | true (default) = fire on every cron match until deleted or auto-expired after 3 days. false = fire once at the next m... |

---

## CronDelete

> cancel a scheduled cron job

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `id` | string | Yes | Job ID returned by CronCreate. |

---

## CronList

> list active cron jobs

---

## ToolSearch

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `query` | string | Yes | Query to find deferred tools. Use "select:<tool_name>" for direct selection, or keywords to search. |
| `max_results` | number | Yes | Maximum number of results to return (default: 5) |

---

