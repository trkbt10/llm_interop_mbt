#!/usr/bin/env node

const fs = require("fs")
const path = require("path")
const readline = require("readline")
const { spawn } = require("child_process")

const FIXTURES_DIR = path.join(__dirname, "..", "testdata", "codex")

let nextId = 1
const pending = new Map()
const allResponses = []
const allNotifications = []

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true })
}

function writeFixture(name, data) {
  const filePath = path.join(FIXTURES_DIR, name)
  fs.writeFileSync(filePath, JSON.stringify(data, null, 2) + "\n")
  console.log(`Wrote: ${name}`)
}

function writeFixtureLines(name, lines) {
  const filePath = path.join(FIXTURES_DIR, name)
  fs.writeFileSync(filePath, lines.map(l => JSON.stringify(l)).join("\n") + "\n")
  console.log(`Wrote: ${name} (${lines.length} lines)`)
}

async function main() {
  ensureDir(FIXTURES_DIR)

  console.log("Starting codex app-server...")
  const child = spawn("codex", ["app-server"], {
    cwd: process.cwd(),
    env: process.env,
    stdio: ["pipe", "pipe", "pipe"],
  })

  child.stderr.setEncoding("utf8")
  child.stderr.on("data", (chunk) => {
    console.error("stderr:", chunk.trimEnd())
  })

  const rl = readline.createInterface({
    input: child.stdout,
    crlfDelay: Infinity,
  })

  rl.on("line", (line) => {
    if (!line.trim()) return
    try {
      const msg = JSON.parse(line)

      // Check if it's a response to a request
      if (msg.id !== undefined && (msg.result !== undefined || msg.error !== undefined)) {
        const key = String(msg.id)
        const handler = pending.get(key)
        if (handler) {
          pending.delete(key)
          handler.resolve(msg)
        }
        allResponses.push({ id: msg.id, msg })
      }
      // Check if it's a server request (has both id and method)
      else if (msg.id !== undefined && msg.method !== undefined) {
        console.log("Server request:", msg.method)
        // Auto-approve for fixtures
        if (msg.method === "item/commandExecution/requestApproval" ||
            msg.method === "item/fileChange/requestApproval" ||
            msg.method === "execCommandApproval" ||
            msg.method === "applyPatchApproval") {
          child.stdin.write(JSON.stringify({ id: msg.id, result: { decision: "acceptForSession" } }) + "\n")
          writeFixture("approval_request.json", msg)
        }
        allNotifications.push(msg)
      }
      // Notification (no id, has method)
      else if (msg.method !== undefined) {
        console.log("Notification:", msg.method)
        allNotifications.push(msg)
      }
    } catch (e) {
      console.error("Parse error:", e.message, "line:", line)
    }
  })

  function request(method, params, timeoutMs = 10000) {
    const id = nextId++
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        pending.delete(String(id))
        reject(new Error(`Timeout: ${method}`))
      }, timeoutMs)

      pending.set(String(id), {
        resolve: (msg) => {
          clearTimeout(timer)
          resolve(msg)
        },
        reject: (err) => {
          clearTimeout(timer)
          reject(err)
        }
      })

      const req = { id, method, params }
      child.stdin.write(JSON.stringify(req) + "\n")
    })
  }

  function notify(method, params) {
    child.stdin.write(JSON.stringify({ method, params }) + "\n")
  }

  try {
    // 1. Initialize
    console.log("\n=== Initialize ===")
    const initResp = await request("initialize", {
      clientInfo: { name: "fixture-capture", version: "1.0.0" },
      capabilities: { experimentalApi: true }
    })
    console.log("Initialize response:", JSON.stringify(initResp, null, 2))
    writeFixture("initialize_response.json", initResp)

    // Send initialized notification
    notify("initialized", {})

    // Wait a bit for any notifications
    await new Promise(r => setTimeout(r, 1000))

    // 2. Thread start
    console.log("\n=== Thread Start ===")
    const threadResp = await request("thread/start", {
      cwd: process.cwd(),
      approvalPolicy: "never",
      serviceName: "fixture-capture",
      personality: "pragmatic",
      experimentalRawEvents: false,
      persistExtendedHistory: false,
      dynamicTools: []
    })
    console.log("Thread start response:", JSON.stringify(threadResp, null, 2))
    writeFixture("thread_start_response.json", threadResp)

    const threadId = threadResp.result?.thread?.id
    if (!threadId) {
      throw new Error("No thread ID in response")
    }

    // 3. Turn start with a simple prompt
    console.log("\n=== Turn Start ===")
    const turnResp = await request("turn/start", {
      threadId,
      input: [{ type: "text", text: "Say hello in one word.", text_elements: [] }],
      cwd: process.cwd(),
      approvalPolicy: "never"
    })
    console.log("Turn start response:", JSON.stringify(turnResp, null, 2))
    writeFixture("turn_start_response.json", turnResp)

    const turnId = turnResp.result?.turn?.id
    if (!turnId) {
      throw new Error("No turn ID in response")
    }

    // Wait for turn to complete (collect events)
    console.log("\n=== Waiting for turn completion ===")
    await new Promise((resolve) => {
      const timeout = setTimeout(resolve, 30000) // 30s max
      const checkInterval = setInterval(() => {
        // Check if we got task_complete
        const complete = allNotifications.find(n =>
          n.params?.msg?.type === "task_complete" ||
          (n.method === "item/completed" && n.params?.item?.type === "agentMessage")
        )
        if (complete) {
          clearTimeout(timeout)
          clearInterval(checkInterval)
          setTimeout(resolve, 2000) // Wait a bit more for final events
        }
      }, 500)
    })

    // Write all collected events
    if (allNotifications.length > 0) {
      writeFixtureLines("events.jsonl", allNotifications)
    }

    // Try to get an error response
    console.log("\n=== Error Response ===")
    const errorResp = await request("invalid/method", {})
    console.log("Error response:", JSON.stringify(errorResp, null, 2))
    writeFixture("error_response.json", errorResp)

  } catch (err) {
    console.error("Error:", err.message)
  } finally {
    console.log("\n=== Cleanup ===")
    child.kill("SIGTERM")
    await new Promise(r => setTimeout(r, 1000))

    console.log(`\nTotal responses: ${allResponses.length}`)
    console.log(`Total notifications: ${allNotifications.length}`)

    // Write summary
    writeFixture("_capture_summary.json", {
      timestamp: new Date().toISOString(),
      responses: allResponses.length,
      notifications: allNotifications.length
    })
  }
}

main().catch(console.error)
