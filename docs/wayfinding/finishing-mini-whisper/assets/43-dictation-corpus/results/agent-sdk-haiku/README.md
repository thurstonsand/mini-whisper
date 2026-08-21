# Haiku 4.5 on the Claude subscription, through the Agent SDK

The same stage 3 as [`built-in-r2`](../built-in-r2/), the same model, a different way of reaching it. `claude-haiku-4-5` there was billed per token against Anthropic's OpenAI-compatible endpoint; here it is the Claude Max subscription, reached the only way Anthropic still allows — Claude Code, driven by the Claude Agent SDK. Raw transcripts are `built-in-r2/stage3-raw.jsonl` unchanged (Parakeet, built-in microphone), the system prompt is `CleanupPrompt.builtIn` lifted out of the Swift source at run time with the spell-out rule in place, and the user message is the same tagged block with `context.before` staged as `BEFORE_CARET`. The runner is [`../../agent-sdk-cleanup/`](../../agent-sdk-cleanup/): it imports `corpus_cleanup.py` and replaces its `complete()` with a pipe to a Node process, so prompt assembly, response shaping, scoring, and these output files are the harness's own code and cannot drift from the API-direct run.

The SDK session is stripped to the bone: no tools, no MCP servers, no settings sources, no skills, no plugins, no session persistence, no partial streaming, one turn. Auth is subscription only — `ANTHROPIC_API_KEY`, `ANTHROPIC_APIKEY`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`, and `ANTHROPIC_BASE_URL` are deleted from the child's environment, and the run aborts unless Claude Code reports a first-party subscription account. It reported `Claude Max`, `apiProvider: firstParty`, `apiKeySource: none`, every time. Exporting a bogus `ANTHROPIC_API_KEY` before a run changes none of that, which is the control that the scrub works.

Three arms:

| directory | arm | what it measures |
| --------- | --- | ---------------- |
| `.` | fresh session per entry, thinking disabled | the app's shape, and the parity comparison against the API-direct run |
| `persistent-session/` | one session for all 27 entries, thinking disabled | whether reusing a session amortizes the startup cost |
| `adaptive-thinking/` | fresh session per entry, SDK default | what the SDK does when nothing tells it not to think |

| file | what it is |
| ---- | ---------- |
| `stage3-claude-haiku-4-5.jsonl` | per-entry cleaned text, match, cleanup latency, ASR latency |
| `stage3-claude-haiku-4-5-score.json` | pass rate, per-tag table, cleanup and end-to-end latency |
| `stage3-claude-haiku-4-5-sdk-timing.json` | the SDK's own split of each entry: session init, model round trip, token counts |

## Headline

| arm | exact match | cleanup median | end to end median | startup per entry | throughput |
| --- | ----------- | -------------- | ----------------- | ----------------- | ---------- |
| API-direct (`built-in-r2`) | 17/27 (63.0%) | 638 ms | 696 ms | — | 84 entries/min |
| **Agent SDK, fresh session** | **17/27 (63.0%)** | 993 ms | 1047 ms | 255 ms | 59 entries/min |
| Agent SDK, persistent session | 17/27 (63.0%) | 627 ms | 685 ms | 4 ms | 85 entries/min |
| Agent SDK, adaptive thinking | 15/27 (55.6%) | 4371 ms | 4425 ms | 253 ms | 6 entries/min |

Cleanup latency mean/min/max: fresh 1015 / 879 / 1590 ms, persistent 705 / 521 / 1262 ms, API-direct 715 / 523 / 1296 ms. ASR contributes a 55 ms median on top. Nothing was throttled in any arm; the subscription served 81 cleanups across the three runs without a single rate limit.

The score reproduces exactly: 17/27, the same number the metered endpoint gave. The transport does not cost accuracy. What it costs is 355 ms, and that number has a shape.

## The startup tax is a subprocess, and it is amortizable

Every `query()` spawns a Claude Code process and waits for its `init` message. That handshake is remarkably stable — 255 ms median, 242 ms min, 340 ms max, tight enough across 27 entries to call it a fixed cost rather than a latency. Subtract it and the fresh arm's model round trip is 719 ms, against the endpoint's 638 ms.

The persistent arm collapses it. One process, one session, 27 turns: init drops to 4 ms median and the round trip to 624 ms — within noise of the API-direct 638 ms. So the subscription path is not intrinsically slower than the metered one; the process spawn is the entire difference, and an app that kept a session warm would pay it once at launch instead of once per dictation.

Reuse is not free in another currency, though. The session accumulates: input tokens climb from 643 on the first entry to 1825 on the twenty-seventh, with no cache reads, because every prior transcript and every prior answer rides along. That is a linear cost on a corpus of 27 and an unbounded one on a dictation app left running all day, and it contaminates the output — the first persistent run scored 16/27, regressing `polish-33` and turning `Kathryn` into `Katheryn` under the influence of the entries before it. The re-run scored 17/27 with `polish-33` still lost. A real implementation wants the warm process without the shared transcript, which the SDK does not currently offer as one thing.

## Adaptive thinking is on by default, and it is a trap here

Left alone, the SDK sends Haiku with adaptive thinking enabled. The corpus feels this hard: 4371 ms median, a 84 s worst case on the capstone entry, and output token counts of 7882 where the answer was a single sentence. Two entries were lost outright — `polish-03`'s self-correction and `polish-39`'s spelling — and `polish-37` came back `Qrok`, which is what over-deliberation on a one-line rewrite produces. Cleanup is a reflex, not a problem; `thinking: { type: 'disabled' }` is not an optimization here but a correctness setting, and the runner defaults to it.

## What the SDK injects

Something, but not much. A control probe with a one-token system prompt and a two-token user message reports 153 input tokens, so roughly 150 tokens of Claude Code's own material sit in front of ours — environment framing, not instructions that survived into behavior. The stripped session reports `tools: []` and `mcp_servers: []`, but still enumerates 14 skills and 40 slash commands even with `skills: []` and `settingSources: []`, so some of that 150 is the SDK describing a machine we told it not to use.

That overhead does not explain a score delta, because there is no score delta to explain. The two arms fail nine of the same ten entries. They differ on exactly two, and in opposite directions:

| entry | expect | API-direct | Agent SDK (fresh) |
| ----- | ------ | ---------- | ----------------- |
| `polish-02` | `Can you post the numbers in the channel?` | pass | dropped the question mark |
| `polish-15` | `Look in /usr/local/bin.` | `/user/local/bin` | pass |

`polish-15` is the entry no model has ever recovered — inferring `usr` from spoken "user" — and this run got it. That is sampling luck in both directions, not a property of the transport. The other nine are the corpus's standing set: `polish-01`, `polish-07`, `polish-11` (quote/unquote Parakeet never delivered), `polish-19`, `polish-20`, `polish-22`, `polish-30`, `polish-36`, `polish-37`. `polish-07` is failed by both arms for different reasons — the endpoint gets the text and loses the single-newline layout, the SDK leaves one `period` untranslated on top of it — and the persistent session is the only arm that has ever matched it exactly.

## Verdict

Subscription Haiku is the same model at the same accuracy, and after the process spawn is amortized, at the same speed. For MiniWhisper it is not the cleanup path — the app cannot require a logged-in Claude Code, and 255 ms of subprocess per dictation is a quarter of the budget the whole pipeline is trying to hold. As a measurement it settles the question the metered run raised: the 638 ms is the model, not the endpoint.
