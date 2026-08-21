# ElevenLabs Scribe v2, built-in microphone

The same built-in-microphone recordings as `results/built-in`, sent to ElevenLabs' batch speech-to-text API: `POST https://api.elevenlabs.io/v1/speech-to-text`, `model_id=scribe_v2`, `language_code=eng`, everything else default — no diarization, no timestamps requested, no entity detection. Account tier `starter`. Machine: Apple M4 Pro, macOS 26.5.2, residential connection.

**Every latency here is a network round trip measured from this machine** — upload, queue, inference, response. It is the number the pipeline would wait for on this connection, and it is not the provider's inference time. Re-measure before betting a profile on it.

| file                | what it is                                      |
| ------------------- | ----------------------------------------------- |
| `stage1.jsonl`      | raw engine output                               |
| `stage1-score.json` | WER detail, per entry                           |
| `stage3-raw.jsonl`  | the transcripts the cleanup matrix is scored on |

Produced by `./transcribe_hosted.py --provider elevenlabs --stage <jsonl> --recordings <dir> --output <out.jsonl>`.

## Headline

| stage | result                                                                                                  |
| ----- | ------------------------------------------------------------------------------------------------------- |
| 1     | WER **0.98%** (2S 0D 0I over 205 words), 23/25 entries clean, 638 ms median / 706 ms mean / 2173 ms max |

**Scribe v2 is the most accurate engine this corpus has measured** — half Parakeet's 1.95% error rate, and the first engine to leave only two errors in 205 words. Both are the same confusable trap everything fails: `colonel` → kernel and `daemon` → demon. It hears every homophone the others trip on, including `site cited on the sign`, `cache`/`cash`, and `brake`/`break`.

It buys that with 638 ms of network, against Parakeet's 55 ms of local compute — an 11x latency multiple, and a dependency on a connection and an account.

## Stage 3 raw

Scribe hears the two things Parakeet silently eats, and hears them cleanly:

- `polish-11`: `She said, quote, it ships tonight, unquote.`
- `polish-38`: `My last name is Sandberg, S-A-N-D-B-E-R-G.`

That is the whole reason the hosted engines matter: with this raw, `polish-38` passes under haiku, gemini, and gpt-oss-120b, and `polish-11` produces `She said, "It ships tonight."` from every capable cleanup model — correct English that the corpus's `expect` rejects only over a comma and a capital. See [e2e-combos](../e2e-combos/README.md).

Two engine-side effects to carry into a stage-3 reading, both of which make its stage 3 a slightly easier task than Parakeet's:

- Scribe drops the terminal spoken `period` on several entries (`polish-11`, `polish-38`), having already decided it was punctuation. Where it does this, the spoken-punctuation axis is measuring the engine, not the cleanup.
- Like whisper and Cohere, it thins disfluencies rather than transcribing every one.

## Caveats

- Starter tier, 90,000-character monthly allowance; nothing throttled across 76 requests.
- `keyterms` biasing is a paid add-on and a separate arm — see [asr-prompting](../asr-prompting/README.md), where it reaches 17/18 recall at 2/8 traps.
- One voice, one microphone, 205 words. A 0.98% WER on 205 words is two errors; a re-run on other audio will move it.
