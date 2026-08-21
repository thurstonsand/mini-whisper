# Cohere Transcribe, built-in microphone

The same built-in-microphone recordings as `results/built-in`, replayed through the native MLX implementation in `mlx-audio` instead of the app's Parakeet engine. Runtime: `mlx-audio` 0.5.0 with MLX 0.32.1. It loads Cohere's upstream safetensors and remaps them to MLX directly, avoiding the prior fixed-window Core ML route that reached about 12 GiB RSS. `sentencepiece` 0.2.2 is an explicit runtime dependency of the Cohere tokenizer, but is not declared by `mlx-audio` 0.5.0.

Model: `CohereLabs/cohere-transcribe-03-2026` revision `b1eacc2686a3d08ceaae5f24a88b1d519620bc09`, upstream `model.safetensors` (4,131,862,976 bytes, SHA-256 `987bd3e141c7bfdb5a78f5db11397ee7737308357e6cc0a3f36a4979b158137a`). This is the unquantized upstream run: no 4- or 8-bit conversion was applied. Python 3.14.6, NumPy 2.5.2, and `huggingface-hub` 1.28.0. Machine: Apple M4 Pro, 48 GB RAM, macOS 26.5.2 (25F84). Weights live in `~/.cache/huggingface/`, outside the repository.

| file | what it is |
| ---- | ---------- |
| `stage1.jsonl` | raw engine output |
| `stage1-score.json` | WER detail, per entry |
| `stage3-raw.jsonl` | raw transcripts for the cleanup matrix |

Produced with:

```sh
set -a && source ../../../../../.env && set +a
uv run --with 'mlx-audio>=0.4.2' --with sentencepiece python transcribe_cohere.py \
  --stage <jsonl> --recordings <dir> --output <out.jsonl>
```

`transcribe_cohere.py` loads the model once, performs one excluded warmup transcription, then times every full `model.generate` call. `latencyMs` is warm wall-clock WAV decode, feature extraction, encoder/decoder inference, and final-text construction. The stage-1 process loaded the model in **1,674 ms** and reached **4,102 MiB** peak RSS; the separately launched stage-3 process, with the model file already in the OS page cache, loaded in 719 ms and reached 4,086 MiB. Neither figure includes the first Hugging Face snapshot download.

## Headline

| stage | result |
| ----- | ------ |
| 1 | WER **3.41%** (6S 1D 0I over 205 words), 20/25 entries clean, 97 ms median / 108 ms mean / 263 ms max |

Cohere is much lighter than the prior Core ML route but still trails Parakeet's 1.95% WER and 55 ms median. It is faster than the measured whisper.cpp alternatives, which each scored 3.90% at 422–487 ms median, while improving their WER by one error on this corpus.

## Stage 3 raw

The requested material survives both cases, verbatim:

- `polish-11`: `She said, "It ships tonight," period.`
- `polish-38`: `My last name is Sandberg, S-A-N-D-B-E-R-G, period.`

The first still recognizes the spoken word `period` rather than attaching it inside the quotation. `stage3-raw.jsonl` is input to cleanup, not a cleanup result.

## Caveats

- This is an `mlx-audio` implementation result, not a MiniWhisper integration or the prior FluidAudio/Core ML artifact. RSS allocation/accounting differs by runtime, but this native MLX process's 4.0 GiB high-water mark directly rebuts the prior roughly 12 GiB result for this route.
- The upstream 4.13 GB safetensors are larger on disk than the resident high-water measurement suggests. The process is suitable for comparison, not evidence that a 4 GB resident model fits MiniWhisper's product footprint.
- Cohere is called with `language="en"`, default punctuation enabled, no VAD, and `max_tokens=256`. Results include punctuation and casing; stage-1 WER normalization ignores punctuation and case.
- The model has no streaming generation in this runtime. These measurements are complete-utterance hold-to-talk transcriptions.
