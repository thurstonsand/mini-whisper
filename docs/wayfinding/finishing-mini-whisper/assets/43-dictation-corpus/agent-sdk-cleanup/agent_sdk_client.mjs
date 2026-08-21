// A request/response pipe over the Claude Agent SDK, so a Python harness can measure the
// subscription path the same way it measures an HTTP endpoint.
//
// The SDK only ships for Node and the corpus harness is Python, so the two are joined by JSONL
// over stdin/stdout: one request line in, one response line out, in order. The process stays alive
// across the whole run because a per-entry `node` spawn would charge the SDK's own module load to
// every entry; what remains per entry is the Claude Code subprocess and its session init, which is
// exactly the fixed cost this measurement is after.
//
// Two arms:
//   --mode fresh    a new query() per entry — one Claude Code subprocess each, no shared history.
//   --mode session  one streaming-input query() for the whole run — the subprocess is spawned once
//                   and every entry is another turn in the same conversation.
//
// Subscription auth only: the API-key variables are scrubbed from this process, and so from the
// child's inherited environment, and the probe line reports what the session authenticated with.

import { createInterface } from "node:readline";

// The SDK is imported by path rather than installed here: nothing under docs/ carries a
// node_modules, and the only copy on this machine is the one pi-doppelclaude already drives the
// subscription with. `--sdk` points at another.
const DEFAULT_SDK = "/Users/thurstonsand/Develop/pi-doppelclaude/node_modules/@anthropic-ai/claude-agent-sdk/sdk.mjs";

const API_KEY_VARIABLES = [
  "ANTHROPIC_API_KEY",
  "ANTHROPIC_APIKEY",
  "ANTHROPIC_AUTH_TOKEN",
  "CLAUDE_CODE_OAUTH_TOKEN",
  "ANTHROPIC_BASE_URL",
];
for (const name of API_KEY_VARIABLES) delete process.env[name];

function parseArguments(argv) {
  const options = {
    mode: "fresh",
    model: "claude-haiku-4-5",
    sdk: DEFAULT_SDK,
    // Claude Code turns adaptive thinking on by default. The endpoint this run is compared
    // against has no such default, so parity means off; `--thinking on` measures the other arm.
    thinking: "off",
  };
  for (let index = 0; index < argv.length; index += 2) {
    const flag = argv[index];
    const value = argv[index + 1];
    if (flag === "--mode") options.mode = value;
    else if (flag === "--model") options.model = value;
    else if (flag === "--sdk") options.sdk = value;
    else if (flag === "--debug-file") options.debugFile = value;
    else if (flag === "--thinking") options.thinking = value;
    else throw new Error(`unknown flag ${flag}`);
  }
  if (options.mode !== "fresh" && options.mode !== "session") {
    throw new Error(`unknown mode ${options.mode}`);
  }
  if (options.thinking !== "on" && options.thinking !== "off") {
    throw new Error(`unknown thinking ${options.thinking}`);
  }
  return options;
}

// Everything the SDK offers for "answer one message and nothing else": no tools, no MCP servers,
// no settings files, no skills, no plugins, no hooks, no session persistence, no partial streaming.
function queryOptions(options, system, maxTurns) {
  const { model, debugFile, thinking } = options;
  return {
    ...(debugFile ? { debug: true, debugFile } : {}),
    ...(thinking === "off" ? { thinking: { type: "disabled" } } : {}),
    env: { ...process.env, ENABLE_CLAUDEAI_MCP_SERVERS: "0", DISABLE_AUTO_COMPACT: "1" },
    systemPrompt: system,
    model,
    tools: [],
    mcpServers: {},
    strictMcpConfig: true,
    settingSources: [],
    skills: [],
    plugins: [],
    persistSession: false,
    includePartialMessages: false,
    permissionMode: "bypassPermissions",
    allowDangerouslySkipPermissions: true,
    ...(maxTurns === undefined ? {} : { maxTurns }),
  };
}

function emit(value) {
  process.stdout.write(`${JSON.stringify(value)}\n`);
}

/** The wall clock the caller pays, plus the SDK's own split of it: `initMs` is how long the child
 * took to announce itself, `apiMs` the model round trip an HTTP endpoint would have charged alone. */
function timings(started, init, result) {
  return {
    totalMs: Number((performance.now() - started).toFixed(1)),
    sdkDurationMs: result.duration_ms,
    apiMs: result.duration_api_ms,
    ttftMs: result.ttft_ms ?? null,
    timeToRequestMs: result.time_to_request_ms ?? null,
    timeToRequestFromSpawnMs: result.time_to_request_from_spawn_ms ?? null,
    initMs: init === null ? null : Number(init.toFixed(1)),
    sessionId: result.session_id,
    numTurns: result.num_turns,
    costUsd: result.total_cost_usd ?? null,
    // Input tokens are the only visible measure of what the SDK put in front of the model: a
    // count far above the corpus prompt's own is an injection, whatever the model says it was.
    inputTokens: result.usage?.input_tokens ?? null,
    cacheReadTokens: result.usage?.cache_read_input_tokens ?? null,
    cacheCreationTokens: result.usage?.cache_creation_input_tokens ?? null,
    outputTokens: result.usage?.output_tokens ?? null,
  };
}

function describeInit(message) {
  return {
    type: "init",
    apiKeySource: message.apiKeySource,
    model: message.model,
    tools: message.tools,
    mcpServers: message.mcp_servers,
    skills: message.skills,
    slashCommands: message.slash_commands?.length ?? null,
    claudeCodeVersion: message.claude_code_version,
  };
}

function assistantText(message) {
  return message.message.content
    .filter((block) => block.type === "text")
    .map((block) => block.text)
    .join("");
}

let query;

async function probe(options) {
  const { model } = options;
  const session = query({
    prompt: (async function* () {})(),
    options: queryOptions(options, "probe", 1),
  });
  try {
    const [account, models] = await Promise.all([session.accountInfo(), session.supportedModels()]);
    emit({
      type: "probe",
      account,
      resolved: models.find((entry) => entry.value === model)?.resolvedModel ?? null,
      serves: models.some((entry) => entry.value === model || entry.resolvedModel === model),
    });
  } finally {
    session.close();
  }
}

/** One Claude Code subprocess per entry: what an app pays when every dictation starts cold. */
async function answerFresh(request, options, reportInit) {
  const started = performance.now();
  let init = null;
  let text = "";
  const session = query({
    prompt: request.user,
    options: queryOptions(options, request.system, 1),
  });
  try {
    for await (const message of session) {
      if (message.type === "system" && message.subtype === "init") {
        init = performance.now() - started;
        if (reportInit) emit(describeInit(message));
      } else if (message.type === "assistant") {
        text += assistantText(message);
      } else if (message.type === "result") {
        if (message.subtype !== "success") {
          throw new Error(`${message.subtype}: ${(message.errors ?? []).join("; ")}`);
        }
        emit({
          type: "response",
          id: request.id,
          text: message.result || text,
          ...timings(started, init, message),
        });
        return;
      }
    }
    throw new Error("stream ended before a result message");
  } finally {
    session.close();
  }
}

/** One subprocess and one conversation for the whole run: each entry is another turn, so the
 * transcript accumulates. The point is the cost, and whether the accumulation changes the answer. */
async function runSession(lines, options, reportInit) {
  const ids = [];
  let system = null;
  let turnStarted = performance.now();

  async function* prompts() {
    for (;;) {
      const { value, done } = await lines.next();
      if (done) return;
      if (!value.trim()) continue;
      const request = JSON.parse(value);
      // The system prompt is fixed for the run; the SDK takes it once, at spawn.
      if (system === null) system = request.system;
      ids.push(request.id);
      turnStarted = performance.now();
      yield {
        type: "user",
        message: { role: "user", content: request.user },
        parent_tool_use_id: null,
        session_id: "corpus",
      };
    }
  }

  // The first line has to be read before the query can be built, because the system prompt is a
  // spawn-time option. Peeking it here keeps `prompts()` the only reader afterwards.
  const first = await lines.next();
  if (first.done) return;
  const firstRequest = JSON.parse(first.value);
  system = firstRequest.system;

  async function* withFirst() {
    ids.push(firstRequest.id);
    turnStarted = performance.now();
    yield {
      type: "user",
      message: { role: "user", content: firstRequest.user },
      parent_tool_use_id: null,
      session_id: "corpus",
    };
    yield* prompts();
  }

  const session = query({
    prompt: withFirst(),
    options: queryOptions(options, system, undefined),
  });
  let answered = 0;
  let init = null;
  let text = "";
  try {
    for await (const message of session) {
      if (message.type === "system" && message.subtype === "init") {
        init = performance.now() - turnStarted;
        if (reportInit) emit(describeInit(message));
      } else if (message.type === "assistant") {
        text += assistantText(message);
      } else if (message.type === "result") {
        if (message.subtype !== "success") {
          throw new Error(`${message.subtype}: ${(message.errors ?? []).join("; ")}`);
        }
        emit({
          type: "response",
          id: ids[answered],
          text: message.result || text,
          ...timings(turnStarted, init, message),
        });
        answered += 1;
        text = "";
        init = null;
      }
    }
  } finally {
    session.close();
  }
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  ({ query } = await import(options.sdk));
  const lines = createInterface({ input: process.stdin, crlfDelay: Infinity })[Symbol.asyncIterator]();
  await probe(options);
  if (options.mode === "session") {
    await runSession(lines, options, true);
    return;
  }
  let reportInit = true;
  for (;;) {
    const { value, done } = await lines.next();
    if (done) return;
    if (!value.trim()) continue;
    await answerFresh(JSON.parse(value), options, reportInit);
    reportInit = false;
  }
}

main().catch((error) => {
  emit({ type: "error", message: error instanceof Error ? error.message : String(error) });
  process.exitCode = 1;
});
