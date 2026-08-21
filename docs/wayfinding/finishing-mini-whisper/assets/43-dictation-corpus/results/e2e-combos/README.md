# End-to-end combos

Stage 3 scored as a whole pipeline: every ASR engine that ran, crossed with every cleanup option, on the same recordings. Accuracy is exact match against `expect`; latency is ASR plus cleanup, so a cell is comparable to any other cell.

```sh
# One cell. --prompt none scores the raw transcript itself; --prompt s1-mini uses the model
# card's own format, since s1-mini has no prompt surface.
./corpus_cleanup.py stage3 stage3-polish.jsonl --raw results/whisper-medium-en/stage3-raw.jsonl \
  --prompt s1-mini --no-api-key --endpoint http://localhost:8317/v1 --model s1-mini \
  --results-dir results/e2e-combos/whisper-medium-en
```

Conditions: built-in microphone. Raws come from [`built-in-r2`](../built-in-r2/) (Parakeet), [`elevenlabs-scribe-v2`](../elevenlabs-scribe-v2/), [`cohere-transcribe`](../cohere-transcribe/), [`groq-whisper-large-v3-turbo`](../groq-whisper-large-v3-turbo/), [`whisper-large-v3-turbo`](../whisper-large-v3-turbo/), [`whisper-medium-en`](../whisper-medium-en/), and [`gemini-transcribe`](../gemini-transcribe/). The three hosted engines' latency is a **network round trip from this machine**, not provider inference time; every cell in their rows inherits that caveat. Cleanup: `CleanupPrompt.builtIn` with no additional instructions — gpt-5.6-luna and gemini-3.6-flash through the gateway at `aig.thurstons.house`, `claude-haiku-4-5` direct against Anthropic's OpenAI-compatible endpoint, `gpt-oss-120b` on Cerebras — plus `llama-server -hf superwhisper/s1-mini-GGUF:Q4_K_M --jinja --chat-template-kwargs '{"enable_thinking":false}' --temp 0` on localhost. **s1-mini receives neither the built-in prompt nor a dictionary, by construction** — its card documents one control line and takes no other instruction — so it is scored on what it does with the raw transcript alone. Whisper's latency excludes per-invocation spawn and model load; see its own READMEs.

## The matrix

Exact match out of 27, with end-to-end median latency (ASR + cleanup):

| engine                                    | none        | s1-mini (local)     | gpt-oss-120b    | claude-haiku-4-5 | gpt-5.6-luna | gemini-3.6-flash         |
| ----------------------------------------- | ----------- | ------------------- | --------------- | ---------------- | ------------ | ------------------------ |
| **ElevenLabs Scribe v2** (638 ms, hosted) | 2 — 581 ms  | 11 — 636 ms         | **16** — 950 ms | **19** — 1313 ms | —            | **21 (77.8%)** — 2443 ms |
| **Parakeet** (55 ms)                      | 1 — 55 ms   | **12** — **107 ms** | 15 — **420 ms** | 17 — **696 ms**  | 17 — 2579 ms | 19 — 1914 ms             |
| **Cohere Transcribe** (97 ms)             | 1 — 126 ms  | 9 — 172 ms          | 10 — 520 ms     | 14 — 854 ms      | 14 — 2650 ms | 16 — 2902 ms             |
| **whisper large-v3-turbo** (487 ms)       | 2 — 498 ms  | 11 — 549 ms         | 11 — 904 ms     | 12 — 1151 ms     | 14 — 3055 ms | 16 — 2802 ms             |
| **Groq whisper turbo** (536 ms, hosted)   | 0 — 536 ms  | 9 — 592 ms          | 10 — 908 ms     | 13 — 1260 ms     | —            | 14 — 2637 ms             |
| **whisper medium.en** (422 ms)            | 2 — 441 ms  | 11 — 488 ms         | 12 — 815 ms     | 13 — 1126 ms     | 14 — 2729 ms | 14 — 2868 ms             |
| **Gemini 3.6 Flash** (3271 ms, hosted)    | 0 — 3271 ms | 10 — 3326 ms        | 14 — 3613 ms    | 16 — 3897 ms     | —            | 18 — 5880 ms             |

The gemini column is Google's direct endpoint for the Parakeet row and the three hosted-engine rows, and the `aig.thurstons.house` gateway for Cohere and the two local whisper rows — the gateway costs about 600 ms at the median and nothing in score ([gemini-direct](../gemini-direct/)). luna was not re-run against the new engines: haiku dominates it outright, so its column is history.

**Scribe v2 takes the crown from Parakeet in every cleanup column but one.** 21/27 with gemini is the best cell this corpus has produced, and 19/27 with haiku matches Parakeet's best on any model. The exception is s1-mini, where Parakeet's 12 still leads — the local model cannot use what the better engine delivered.

What Parakeet keeps is the axis it always had: it is 583 ms cheaper than Scribe on every single cell, needs no network and no account, and its cells are the only ones a plane can run. Parakeet + gpt-oss-120b at 15/27 in 420 ms remains the fastest respectable pipeline in the table; Scribe + gpt-oss-120b buys one more entry for 530 ms.

The other three hosted rows are negative results. Groq's turbo is the same weights as the local whisper row at the same accuracy and the same wall-clock — hosting whisper buys nothing on this machine. Gemini-as-engine is last on both axes.

## Cohere Transcribe + s1-mini, the headline ask

superwhisper's recommended offline stack **loses to Parakeet + s1-mini on both axes**: 9/27 at 172 ms against 12/27 at 107 ms. Cohere is a real engine — 3.41% stage-1 WER at a 97 ms median and 4.1 GB RSS through `mlx-audio`, which is a very different animal from the 532 ms / 12 GB Core ML attempt in [asset 26](../../../26-cohere-transcription-model/) — but Parakeet is nearly twice as accurate at 1.95% and almost twice as fast.

The three entries Cohere + s1-mini loses are all ASR damage, not cleanup damage: it writes `thorston@example.com`, inserts a contraction (`We've tried it` for "We tried it"), and hears "write up home about ducks" for "write a poem about ducks". That last one breaks the no-instruction-following invariant by garbling it rather than by obeying it, which the score cannot distinguish and a reader should.

What Cohere does have is ears Parakeet lacks. It is the only engine besides whisper that hears the two things Parakeet silently eats:

| entry       | Parakeet                               | Cohere Transcribe                                    |
| ----------- | -------------------------------------- | ---------------------------------------------------- |
| `polish-11` | `She said it ships tonight, period.`   | `She said, "It ships tonight," period.`              |
| `polish-38` | `My last name is Sandberg, San Dberg.` | `My last name is Sandberg, S-A-N-D-B-E-R-G, period.` |

Cohere resolves `polish-11`'s quote/unquote into actual quotation marks in the raw transcript, before any cleanup runs. That is the entry no cleanup model can win on Parakeet at any price. It is one entry, and it does not pay for the other three, but it is the precise shape of what a second engine would buy.

Like whisper large-v3-turbo, Cohere silently deletes disfluencies — `polish-01` arrives as "So, I think we should probably ship it today" with both spoken `um`s gone — so its disfluency column measures a slightly easier task.

## The accuracy-per-millisecond frontier

Across both engines worth choosing between, six points are undominated — nothing above and to the left of them:

| stack                    | exact match | end to end |
| ------------------------ | ----------- | ---------- |
| Parakeet + s1-mini       | 12/27       | **107 ms** |
| Parakeet + gpt-oss-120b  | 15/27       | 420 ms     |
| Parakeet + haiku 4.5     | 17/27       | 696 ms     |
| Scribe v2 + gpt-oss-120b | 16/27       | 950 ms     |
| Scribe v2 + haiku 4.5    | 19/27       | 1313 ms    |
| **Scribe v2 + gemini**   | **21/27**   | 2443 ms    |

Parakeet + gemini (19/27, 1914 ms) is the one former leader that falls off the frontier: Scribe + haiku matches its score in two thirds of the time. Everything below 700 ms is still Parakeet's, and everything above 19/27 is now Scribe's.

On Parakeet alone, the four cleanup models remain a clean staircase and nothing on it is dominated:

| cleanup                 | exact match | end to end | throughput      |
| ----------------------- | ----------- | ---------- | --------------- |
| s1-mini (local)         | 12/27 44.4% | 107 ms     | —               |
| gpt-oss-120b (Cerebras) | 15/27 55.6% | 420 ms     | 149 entries/min |
| claude-haiku-4-5        | 17/27 63.0% | 696 ms     | 84 entries/min  |
| gpt-5.6-luna            | 17/27 63.0% | 2579 ms    | —               |
| gemini-3.6-flash        | 19/27 70.4% | 2532 ms    | —               |

**haiku 4.5 dominates luna outright** — same 17/27, a quarter of the latency — so luna has no remaining argument on this corpus. gemini keeps the accuracy crown by two entries and charges 3.6x haiku's latency for them. gpt-oss-120b on Cerebras is the interesting middle: 420 ms end to end including the engine, which is a whole dictation cleaned in under half a second.

gpt-oss-120b's two lost entries relative to haiku are not near-misses, and they should be read before the speed is banked. It leaves `period` untranslated twice, appends a period to the mid-sentence dictation the prompt explicitly forbids, and writes `GrokQ` for the spell-out. Those are rule failures. Neither hosted run was throttled: 27 entries took 11 s on Cerebras and 19 s on Anthropic.

All four models accepted the app's request body unchanged — model, two messages, `stream: false`, no temperature, no token cap. Anthropic's OpenAI-compatible endpoint at `api.anthropic.com/v1` rejected nothing, and `claude-haiku-4-5` resolves to `claude-haiku-4-5-20251001`.

## Parakeet + gemini vs the local stack

gemini-3.6-flash on Parakeet is the accuracy leader at 19/27, and it costs 2.5 s. s1-mini on Parakeet reaches 12/27 in 107 ms. The seven-entry gap is not spread evenly — it is almost entirely the axes s1-mini was never told about:

| axis                     | Parakeet + s1-mini | Parakeet + gemini |
| ------------------------ | ------------------ | ----------------- |
| spell-out                | 0/3                | 3/3               |
| identifier               | 0/3                | 1/3               |
| context (`BEFORE_CARET`) | 0/3                | 1/3               |
| symbols                  | 2/5                | 3/5               |
| disfluency               | 1/4                | 2/4               |
| spoken-punctuation       | 3/5                | 4/5               |
| rule (invariants)        | 4/5                | 4/5               |

s1-mini holds the invariants — it does not answer `polish-27`'s question, does not obey `polish-28`'s embedded instruction, preserves contractions and register — and it converts ordinary spoken punctuation and filenames correctly. What it never does is anything the built-in prompt asks for and its own card does not: it leaves "Grok with a Q" and "S-A-N-D-B-E-R-G" verbatim, never forms an identifier, and ignores the staged field context, because it never receives any of those instructions. Those failures are structural, not quality.

## Cleanup earns its place

The `none` column is the control: raw transcripts score 1–2 of 27 whatever the engine, because the corpus is read with its punctuation spoken aloud. Every cleanup option is a large improvement over none. The engine choice moves the final answer by three to five entries; the cleanup choice moves it by eight to eighteen.

Two engine-side effects worth naming, both from whisper:

- large-v3-turbo silently deletes disfluencies. `polish-01` arrives as "So I think we should probably ship it today" with both spoken `um`s already gone, so the disfluency axis stops measuring cleanup on that engine.
- whisper pre-resolves symbols the corpus meant to test — medium.en writes `Thurston@example.com` and `fetchUsers` before any cleanup runs — while large-v3-turbo destroys the same email into `thurston.example.com`. Whisper's stage-3 rows are therefore measuring a slightly easier and slightly different task than Parakeet's.

Conversely, Parakeet swallows `quote`/`unquote` and letter-by-letter spellings that both whisper models transcribe cleanly. `polish-11` and `polish-38` are unwinnable on Parakeet for any cleanup model.

## The two Parakeet deletions, on every hosted engine

Every engine measured except Parakeet hears both entries:

| engine             | `polish-11` raw                                       | `polish-38` raw                                             |
| ------------------ | ----------------------------------------------------- | ----------------------------------------------------------- |
| Parakeet           | `She said it ships tonight, period.`                  | `My last name is Sandberg, San Dberg.`                      |
| Scribe v2          | `She said, quote, it ships tonight, unquote.`         | `My last name is Sandberg, S-A-N-D-B-E-R-G.`                |
| Groq whisper turbo | `She said, quote, it ships tonight, unquote, period.` | `My last name is Sandberg, comma, S-A-N-D-B-E-R-G, period.` |
| Gemini             | `She said quote it ships tonight unquote period`      | `My last name is Sandberg comma S A N D B E R G period.`    |
| Cohere             | `She said, "It ships tonight," period.`               | `My last name is Sandberg, S-A-N-D-B-E-R-G, period.`        |

`polish-38` converts: it passes under haiku, gemini, and gpt-oss-120b on Scribe's raw, and under gemini on Groq's. A better engine genuinely buys that entry.

`polish-11` scores as a failure everywhere, and it should not. Given the words, every capable cleanup model writes `She said, "It ships tonight."` — correct English. The corpus `expect` is `She said "it ships tonight."`, without the comma and without the capital. **The entry is no longer measuring the engine or the model; it is measuring a punctuation opinion**, and it belongs on the same list as `polish-15` and `polish-20` as an expectation to settle rather than a capability to shop for.
