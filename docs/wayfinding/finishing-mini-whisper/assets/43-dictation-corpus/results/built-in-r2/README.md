# Built-in microphone, second run — refreshed stage 3

Same conditions as [`built-in`](../built-in/): MacBook built-in microphone, quiet room, engine `parakeet-tdt-0.6b-v2-coreml @ ee09c56` with the CTC boost model, int8 encoder, dev-channel artifact. Cleanup: `CleanupPrompt.builtIn` with no additional instructions, over four providers — gpt-5.6-luna and gemini-3.6-flash through the gateway at `aig.thurstons.house`, `claude-haiku-4-5` direct against Anthropic's OpenAI-compatible endpoint at `api.anthropic.com/v1` (the alias resolves to `claude-haiku-4-5-20251001`), and `gpt-oss-120b` on `api.cerebras.ai/v1`. The app's request body went to all four unchanged: model, two messages, `stream: false`, no temperature, no token cap. Nothing rejected it.

Two things changed under it, so this run supersedes both `built-in`'s and `built-in-spellout`'s stage 3 numbers:

- `polish-11`, `polish-14`, `polish-27`, and `polish-33` were re-recorded, because the first run's takes lost the material cleanup was supposed to work on.
- `CleanupPrompt.builtIn` gained the spell-out rule: spelled letters say how to write the word and the aside disappears.

Stage 1 and stage 2 were not re-recorded and are not re-scored here; `built-in` remains their run of record.

| file | what it is |
| ---- | ---------- |
| `stage3-raw.jsonl` | Parakeet's transcripts on the refreshed recordings |
| `stage3-<model>.jsonl` | per-entry cleaned text, match, cleanup latency, ASR latency |
| `stage3-<model>-score.json` | pass rate, per-tag table, cleanup and end-to-end latency |

## Headline

| model | exact match | cleanup median | end to end median | throughput |
| ----- | ----------- | -------------- | ----------------- | ---------- |
| gemini-3.6-flash | **19/27 (70.4%)** | 2476 ms | 2532 ms | — |
| gpt-5.6-luna | 17/27 (63.0%) | 2521 ms | 2579 ms | — |
| claude-haiku-4-5 | 17/27 (63.0%) | **638 ms** | 696 ms | 84 entries/min |
| gpt-oss-120b (Cerebras) | 15/27 (55.6%) | **366 ms** | 420 ms | 149 entries/min |

Against the old raw luna and gemini were 15/27 and 15/27 with the spell-out rule, 15/27 and 12/27 without it. Both now pass all three spell-out entries — but only because the rule tells them to drop an aside; see below for what the engine actually delivered.

The two direct endpoints reshape the frontier. haiku 4.5 matches luna's accuracy at a quarter of its latency, and gpt-oss-120b on Cerebras gives up two more entries for a 366 ms median — an end-to-end dictation, engine included, under half a second. Neither run was throttled once; 27 entries took 19 s and 11 s of wall clock respectively.

gpt-oss-120b pays for its speed in ways worth naming, because they are not the usual near-misses. It leaves `period` untranslated twice (`polish-11`, and `polish-28` — the no-instruction-following invariant, which it otherwise holds), appends a period to the mid-sentence dictation `polish-30` that the prompt explicitly forbids, and mangles the spell-out into `GrokQ`. Those are rule failures, not taste failures. haiku's ten misses are the same set as luna's: `/user/local/bin`, lowercase `p.m.`, the capitalized bare ending, `polish-33`'s grammar, and the identifier axis.

## The re-recorded four

| entry | was | now | verdict |
| ----- | --- | --- | ------- |
| `polish-14` (email) | `example.cod` | `The address is thurston at example.com period.` | fixed; both models pass |
| `polish-27` (no-answering) | "this door close" | `What time does the store close? question mark` | fixed; both models pass |
| `polish-33` (grammar) | ASR loss | `Him and me was going to review it tomorrow.` | valid stage-3 case now; three of four models pass |
| `polish-11` (quotes) | quote/unquote lost | `She said it ships tonight, period.` | **still lost** |

`polish-11` is not a recording defect. Both whisper models transcribed the same WAV as `She said quote it ships tonight unquote period`, so the speaker said the words and Parakeet silently swallows them. The same holds for `polish-38`: whisper heard `S-A-N-D-B-E-R-G`, Parakeet heard `San Dberg`. Both entries measure Parakeet's stage 1, not any model's stage 3 — a cleanup pass cannot restore a quotation mark it was never told about.

`polish-33` is now a real result and it discriminates: luna, haiku 4.5, and gpt-oss-120b all write "He and I were going to review it tomorrow", while gemini leaves the dialect alone. The prompt says to preserve meaningful wording and make only ordinary dictation edits, so gemini's reading is defensible — which makes this entry a question about what `expect` should demand, not a model failure.

## Remaining failures

Seven entries are failed by all four models: `polish-01` (the dropped "just"), `polish-11` (quote/unquote, see above), `polish-15` (`/user/local/bin` — nothing infers `usr`), `polish-20`, `polish-22` (`p.m.` kept lowercase), `polish-30` (leading capital on a mid-sentence dictation), and `polish-36` (the capstone). `polish-19` is failed by three of four. Those eight are where the prompt — or the expectation — has work left, since no amount of model shopping moves them.

gemini alone fails `polish-20` (`5` where `expect` wants `five`) and normalizes `twenty` to `20` in the capstone. luna alone fails `polish-07`'s single-newline layout, drops the leading "So"/"Okay" of two entries, adds `()` to `fetchUsers`, and loses "The address is" from the email entry. haiku fails `polish-07`'s layout the same way luna does and leaves `API controller` unjoined. gpt-oss-120b adds `polish-03` (em dashes where `expect` wants commas) and `polish-39` (`Katherine`, spelling ignored) on top of the rule failures above.
