# Groq whisper-large-v3-turbo, built-in microphone

The same built-in-microphone recordings as `results/built-in`, sent to Groq's OpenAI-shaped transcription endpoint: `POST https://api.groq.com/openai/v1/audio/transcriptions`, `model=whisper-large-v3-turbo`, `language=en`, `response_format=json`. Free tier. Machine: Apple M4 Pro, macOS 26.5.2, residential connection.

This is the same model weight as [`whisper-large-v3-turbo`](../whisper-large-v3-turbo/), run on somebody else's hardware, which makes the pair a clean read on what the hosting is worth.

**Every latency here is a network round trip measured from this machine** — upload, queue, inference, response — not the provider's inference time. Rate-limit waits are excluded from `latencyMs` and reported separately.

| file                | what it is                                      |
| ------------------- | ----------------------------------------------- |
| `stage1.jsonl`      | raw engine output                               |
| `stage1-score.json` | WER detail, per entry                           |
| `stage3-raw.jsonl`  | the transcripts the cleanup matrix is scored on |

Produced by `./transcribe_hosted.py --provider groq --stage <jsonl> --recordings <dir> --output <out.jsonl>`.

## Headline

| stage | result                                                                                                  |
| ----- | ------------------------------------------------------------------------------------------------------- |
| 1     | WER **3.41%** (7S 0D 0I over 205 words), 19/25 entries clean, 523 ms median / 597 ms mean / 1902 ms max |

Groq's turbo is a hair better than the same model locally — 3.41% against whisper.cpp's 3.90%, one fewer error and no hallucinated insertion — and its 523 ms round trip is inside the local model's 487 ms of compute. Which is the point worth taking: **hosting this model buys nothing on this machine.** whisper.cpp on an M4 Pro already answers as fast as Groq does over the network, at the same accuracy, without an account. The hosted case for whisper is a machine that cannot run it, not a machine that can.

Errors are the confusable axis, as always: `site cited` → `sight sighted`, `colonel` → kernel, `steady` → study, `cash` → cache, `daemon` → demon, `brake` → break.

## Stage 3 raw

Groq hears both entries Parakeet eats, and hears them most literally of any engine measured:

- `polish-11`: `She said, quote, it ships tonight, unquote, period.`
- `polish-38`: `My last name is Sandberg, comma, S-A-N-D-B-E-R-G, period.`

But its stage 3 is otherwise damaged in the same ways the local whisper is, and that costs it the e2e matrix. `polish-14`'s email arrives as `thurston.example.com` — the spoken `at` resolved to a dot, unrecoverable. `polish-27` is misheard as `What time does this door close`. `polish-01` arrives with both spoken `um`s already deleted, and `polish-16` and `polish-03` arrive with symbols and numbers pre-resolved. It tops out at 14/27 with gemini, four behind Parakeet.

## Caveats

- Free tier: the stage-3 run absorbed 69 s of 429 waiting across 27 entries and stage 2's conditioned arm 72 s. None of it entered a latency; all of it would matter to a real user's throughput on this tier.
- The `prompt` parameter is a real conditioning surface and is measured separately in [asr-prompting](../asr-prompting/README.md).
