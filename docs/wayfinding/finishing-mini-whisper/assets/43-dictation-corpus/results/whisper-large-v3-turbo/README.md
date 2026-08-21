# whisper.cpp large-v3-turbo, built-in microphone

The same built-in-microphone recordings as `results/built-in`, replayed through whisper.cpp instead of the app's Parakeet engine. Engine: `whisper-cli` 1.9.2 (Homebrew `whisper-cpp`, ggml 0.20.2, Metal + BLAS backends), model `ggml-large-v3-turbo.bin` (1,624,555,275 bytes, sha256 `1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69`, from huggingface `ggerganov/whisper.cpp`, unquantized f16). Flags: `--language en --no-timestamps --output-json`, everything else default — 5 beams, best-of 5, temperature fallback on, 4 threads, flash attention on. Machine: Apple M4 Pro, 48 GiB, macOS 26.5.2. Models live in `~/.cache/whisper.cpp`, outside the repo.

| file | what it is |
| ---- | ---------- |
| `stage1.jsonl` | raw engine output |
| `stage1-score.json` | WER detail, per entry |
| `stage3-raw.jsonl` | the transcripts the cleanup matrix is scored on |

Produced by `./transcribe_whisper.py --stage <jsonl> --recordings <dir> --output <out.jsonl> --model ~/.cache/whisper.cpp/ggml-large-v3-turbo.bin`.

## Headline

| stage | result |
| ----- | ------ |
| 1 | WER **3.90%** (7S 0D 1I over 205 words), 18/25 entries clean, 487 ms median / 496 ms mean / 651 ms max |

Parakeet's 1.95% at a 55 ms median still wins both axes, and the latency gap is wider than it looks. `whisper-cli` is a one-shot process, so `latencyMs` here is whisper's own `total time - load time` — the transcription work with the model already resident, which is the only number comparable to Parakeet's warm in-process 55 ms. It still excludes a median **474 ms** (max 551 ms) of process spawn, backend init, and model load that a real per-utterance CLI invocation would pay on top. A resident whisper.cpp server would pay the load once; nothing here measures that configuration.

Stage 1's errors are the same confusable axis Parakeet failed on, plus more of it: colonel→kernel, cash→cache, daemon→demon, brake→break, steady→study, heir→air, and `site cited`→`sight sighted` (two words in one sentence). One insertion: confusable-24 ends `an air of calm and`, a trailing word that was never spoken.

## Stage 3 raw

`stage3-raw.jsonl` is input, not a result — the cleanup matrix replays it through `CleanupPrompt.builtIn` and scores the cleaned text against `expect`. Failure modes worth carrying into that reading:

- **The model cleans up on its own.** polish-01 came back as `So I think we should probably ship it today.` — both spoken `um`s deleted by the ASR. Disfluency entries can no longer distinguish "the cleanup removed the filler" from "the engine never delivered it".
- **Invented quotation marks.** polish-07 and polish-29 arrive wrapped in `"` that were not spoken.
- **polish-14** (`thurston at example dot com`) came back as `thurston.example.com` — the `at` was resolved to a dot, so the email address is unrecoverable downstream.
- **polish-15** `slash user slash local slash bin` became the literal path `/user/local/bin` — the expected `/usr/local/bin` needs the cleanup to know the convention, and the raw text now looks confident rather than ambiguous.
- **polish-27** was misheard as `What time does this door close` (reference: `the store close`).
- **polish-30**, a deliberately bare mid-sentence ending, lost the trailing ellipsis but kept the words.
- Symbols and numbers are partly resolved already: `--help`, `--filter`, `3:30 p.m.`, `2.3.1`.

No `[BLANK_AUDIO]`, no `(wind blowing)`, no non-speech bracket artifacts in either stage — every entry produced speech text.
