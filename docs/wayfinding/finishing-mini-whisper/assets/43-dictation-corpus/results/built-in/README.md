# Built-in microphone, first run

MacBook built-in microphone, quiet room, one take per entry. Engine: `parakeet-tdt-0.6b-v2-coreml @ ee09c56` with the CTC boost model, dev-channel artifact, int8 encoder. Cleanup: the gateway at `aig.thurstons.house`, `CleanupPrompt.builtIn` with no additional instructions.

| file | what it is |
| ---- | ---------- |
| `stage1.jsonl` | raw engine output, no dictionary |
| `stage1-score.json` | WER detail, per entry |
| `stage2-bare.jsonl` | stage 2 with no vocabulary staged |
| `stage2-boosted.jsonl` | stage 2 with the 15-term `wants` union staged |
| `stage2-score.json` | recall, false positives, latency, both runs |
| `stage3-raw.jsonl` | the transcripts cleanup is scored on |
| `stage3-<model>.jsonl` | per-entry cleaned text, match, latency |
| `stage3-<model>-score.json` | pass rate, per-tag table, full detail |

## Headline

| stage | result |
| ----- | ------ |
| 1 | WER **1.95%** (4S 0D 0I over 205 words), 21/25 entries clean, 55 ms median |
| 2 | `wants` recall **27.8% → 88.9%** with boost; `traps` false positives **0% → 62.5%**; +98 ms median |
| 3 | exact match **12/27 (44.4%)** gpt-5.6-luna at 2.6 s median; **15/27 (55.6%)** gemini-3.6-flash at 2.4 s median |

Stage 1's four errors are all confusables the engine resolved the wrong way: colonel→kernel, week→weak, cash→cache, daemon→demon. Nothing else in the stage was misheard.

Stage 2 is the sharp result. Boost buys back nine of thirteen missed terms and bites five of eight traps — a parakeet becomes a `Parakeet`, a key chain becomes the `Keychain`, cerebral becomes `Cerebras`. `Qwen` survives neither run.

Stage 3's spell-out axis: gemini-3.6-flash produced `Groq` from "Grok with a Q" unprompted; gpt-5.6-luna did not. Neither model handled the letter-by-letter spelling or "Katherine with a K and a Y". Several other failures are stage 1 damage arriving in stage 3's lap — `example.cod`, a lost quote/unquote, a "dash dash" heard as one dash.
