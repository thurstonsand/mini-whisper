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

The pool is fresh-mode only, and reports how many distinct session IDs a run used so isolation is measured rather than claimed — 150 calls, 150 sessions. It is not a free substitute for the metered endpoint, though: Claude Code's own framing rides in front of every request, and the shipped prompt scores 19.00/25 through `api.anthropic.com` against 16.25/25 through the SDK at the same n. Use it where the framing is not what is being measured — an Opus proposer writing prose, a screening pass whose survivors get re-scored.

Results: [`../results/agent-sdk-haiku/`](../results/agent-sdk-haiku/).
