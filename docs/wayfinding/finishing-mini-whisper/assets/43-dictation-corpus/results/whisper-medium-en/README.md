# whisper.cpp medium.en, built-in microphone

The same built-in-microphone recordings as `results/built-in`, replayed through whisper.cpp instead of the app's Parakeet engine. Engine: `whisper-cli` 1.9.2 (Homebrew `whisper-cpp`, ggml 0.20.2, Metal + BLAS backends), model `ggml-medium.en.bin` (1,533,774,781 bytes, sha256 `cc37e93478338ec7700281a7ac30a10128929eb8f427dda2e865faa8f6da4356`, from huggingface `ggerganov/whisper.cpp`, unquantized f16). Flags: `--language en --no-timestamps --output-json`, everything else default — 5 beams, best-of 5, temperature fallback on, 4 threads, flash attention on. Machine: Apple M4 Pro, 48 GiB, macOS 26.5.2. Models live in `~/.cache/whisper.cpp`, outside the repo.

| file | what it is |
| ---- | ---------- |
| `stage1.jsonl` | raw engine output |
| `stage1-score.json` | WER detail, per entry |
| `stage3-raw.jsonl` | the transcripts the cleanup matrix is scored on |

Produced by `./transcribe_whisper.py --stage <jsonl> --recordings <dir> --output <out.jsonl> --model ~/.cache/whisper.cpp/ggml-medium.en.bin`.

## Headline

| stage | result |
| ----- | ------ |
| 1 | WER **3.90%** (8S 0D 0I over 205 words), 17/25 entries clean, 422 ms median / 425 ms mean / 498 ms max |

Same WER as large-v3-turbo by a different route: one more substitution, no insertion, one fewer clean entry — and it is faster, which makes the English-only medium the better of the two whisper options on this corpus. Both still lose to Parakeet's 1.95% at a 55 ms median.

`latencyMs` is whisper's own `total time - load time`, the transcription work with the model already resident, which is the only number comparable to Parakeet's warm in-process 55 ms. `whisper-cli` is a one-shot process, so it also excludes a median **462 ms** (max 554 ms) of process spawn, backend init, and model load per entry. A resident whisper.cpp server would pay the load once; nothing here measures that configuration.

Stage 1's eight substitutions are all confusables: colonel→kernel, cash→cache, daemon→demon, brake→break, steady→study, their→the, heir→air, and `cited`→`sited`.

## Stage 3 raw

`stage3-raw.jsonl` is input, not a result — the cleanup matrix replays it through `CleanupPrompt.builtIn` and scores the cleaned text against `expect`. Failure modes worth carrying into that reading:

- **polish-28** came back as `write at home about ducks` (reference: `write a poem about ducks`) — the entry tests that an embedded instruction is transcribed rather than obeyed, and it now arrives damaged.
- **polish-15** `slash user slash local slash bin` became `/user/local/bin/` — a wrong path with a trailing slash, so `expect`'s `/usr/local/bin` is out of reach downstream.
- **polish-07** arrives wrapped in quotation marks that were not spoken.
- **polish-14** and **polish-19** are already resolved by the ASR: `Thurston@example.com` (capitalized) and `fetchUsers` in camel case, before any cleanup ran.
- **polish-11** and **polish-33** came back with no punctuation and no capitalization at all, unlike their neighbors — worth knowing when a cleanup failure looks like a casing problem.
- Fillers survive here: polish-01 keeps both spoken `um`s, so the disfluency entries still test what they were written to test. large-v3-turbo deletes them.

No `[BLANK_AUDIO]`, no `(wind blowing)`, no non-speech bracket artifacts in either stage — every entry produced speech text.
