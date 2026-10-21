# Agent SDK cleanup runner

`corpus_cleanup.py` measures stage 3 over HTTP. Anthropic no longer sells the Claude subscription that way, so a subscription model is reachable only through Claude Code and the Claude Agent SDK. This runner keeps everything the harness measures and swaps only the transport.

| file                          | what it is                                                                                                                                                                                                                                   |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `corpus_cleanup_agent_sdk.py` | the entry point: imports `corpus_cleanup.py`, rebinds its `complete()` to an SDK pipe, then hands off to `run_stage3` so the score file and JSONL are byte-comparable with an API-direct run                                                 |
| `agent_sdk_client.mjs`        | a Node process speaking JSONL over stdin/stdout, because the SDK is TypeScript and the harness is Python                                                                                                                                     |
| `sdk_pool.py`                 | the same transport for the search loops: one pipe per worker thread, fresh session per entry, exposed as `complete()` so [`tune.py`](../results/prompt-tuning-haiku/tune.py)'s `sdk-haiku` and `sdk-opus` providers cannot tell it from HTTP |

```sh
./corpus_cleanup_agent_sdk.py ../stage3-polish.jsonl \
  --raw ../results/built-in-r2/stage3-raw.jsonl \
  --results-dir ../results/agent-sdk-haiku

./corpus_cleanup_agent_sdk.py ../stage3-polish.jsonl \
  --raw ../results/built-in-r2/stage3-raw.jsonl --mode session \
  --results-dir ../results/agent-sdk-haiku/persistent-session
```

`--mode fresh` spawns a Claude Code subprocess per entry; `--mode session` reuses one for the whole run, which amortizes the spawn and accumulates the transcript. `--thinking off` is the default because Claude Code enables adaptive thinking and the endpoints this is compared against do not; `--thinking on` measures that arm. Each run also writes `stage3-<model>-sdk-timing.json` — session init, model round trip, and token counts per entry — which is where the SDK's fixed cost is visible.

Auth is the subscription and nothing else: `ANTHROPIC_API_KEY`, `ANTHROPIC_APIKEY`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`, and `ANTHROPIC_BASE_URL` are removed from the child's environment, and the run aborts unless Claude Code reports a first-party account with a subscription. `claude auth login` is the prerequisite.

The SDK is imported from `pi-doppelclaude`'s `node_modules` rather than installed here, since nothing under `docs/` carries a `node_modules`; `--sdk` points the client at another copy.

The pool is fresh-mode only, and reports how many distinct session IDs a run used so isolation is measured rather than claimed — 150 calls, 150 sessions.

## This is the only transport now

As of [round 4](../results/prompt-tuning-r4/README.md) the metered endpoint is gone: `api.anthropic.com` was removed from `tune.PROVIDERS`, and `corpus_cleanup.py` refuses an endpoint pointed at it. The Anthropic key pays for transcription and nothing else. Earlier text here said the pool "is not a free substitute for the metered endpoint" and cited 19.00/25 against 16.25/25; the second half of that sentence is still true and the first half is no longer a choice anyone has.

So the framing has to be described exactly rather than warned about.

**It is one injected block of about 119 tokens, and it is unconditional.** A request of `system: "x"`, `user: "x"` reports 123 input tokens. It is not in the system prompt — a plain-string `systemPrompt` already replaces Claude Code's preset — but an injected meta user turn ahead of ours, which the model will quote back on request:

```text
# userEmail
The user's email address is <account address>.
# currentDate
Today's date is <today>.

      IMPORTANT: this context may or may not be relevant to your tasks. You should not respond to this context unless it is highly relevant to your task.
```

That is roughly 55 of the 119 tokens; the rest is its `<system-reminder>` wrapper and Claude Code's one residual line.

**`settingSources: []` already prunes the other half, and this is the non-obvious part.** The CLI assembles git status and `CLAUDE.md` into the same context block, so a run from inside a repository could have carried far more. It does not: the floor measured from an empty non-git directory is 123 tokens, identical. Nothing further is removable — the SDK's `Options` type has no switch for the environment context, and its nearest relative, `additionalContext`, only adds. `--debug-file` does not help either; it logs CA certificates, plugin init and an `[API REQUEST]` line, never a request body.

**What the block costs is measured, and it is 1.80 points.** The prompt `CleanupPrompt.builtIn` shipped after round 3 scores **18.50/25 on the frozen objective through `api.anthropic.com`** and **16.70/25 through this pool**, n=10 each, same prompt and same frozen raws. The loss is concentrated rather than diffuse: `polish-07` goes from failing 0 of 10 to 10 of 10, leaving the dictated word *period* standing inside "the review period", and `polish-02` drops a question mark 5 times in 10. Round 2 measured the same gap at 2.75 points on a different prompt and lost the same entries, so the effect replicates.

Every number measured before round 4 is therefore on the far side of a transport change and must not be compared with one measured after it.

Results: [`../results/agent-sdk-haiku/`](../results/agent-sdk-haiku/).
