# Cohere Transcribe at 4-bit, Superwhisper's configuration

Superwhisper's local Cohere Transcribe runs `CohereLabs/cohere-transcribe-03-2026` through MLX at 4-bit on the GPU; its October 20 release made that faster and better on long recordings without a new checkpoint. This run reproduces the configuration rather than the app. The weights are the community conversion [`lyzgeorge/cohere-transcribe-03-2026-mlx-4bit`](https://huggingface.co/lyzgeorge/cohere-transcribe-03-2026-mlx-4bit) at `f2f6d89`, Apache 2.0 like upstream, run by `mlx-audio` 0.6.1, which splits audio past 30 s at low-energy points. Superwhisper's own runtime is closed, so its speed-ups are not in these numbers.

`beshkenadze/cohere-transcribe-03-2026-mlx-4bit`, the build `mlx-audio-swift` links, uses the Swift port's weight names and does not load in Python `mlx-audio`.

Produced with `./bakeoff.py run cohere-transcribe-4bit --label cohere-transcribe-4bit`, against a same-session Parakeet v2 rerun; the full table is [comparison.txt](comparison.txt).

## Headline

| measure | Parakeet v2 | Cohere 4-bit |
| --- | --- | --- |
| Stage 1 WER / holdout | **1.95%** / 2.46% | 3.41% / 2.46% |
| Longform WER | 8.11% | **6.88%** |
| Stage 2 bare `wants` | 5/18 | 5/18 |
| Seam fixtures | no defects | no defects |
| Latency, short dictation (median) | **39 ms** | 82 ms |
| Latency, longform (median) | **104 ms** | 631 ms |
| Model on disk | **464 MB** | 1,510 MB |
| Peak memory, warm process | **~125 MiB** | 1,625 MiB |

Stage 1 matches the full-precision run in [cohere-transcribe](../cohere-transcribe/) error for error, so 4-bit costs this corpus no accuracy. Quantizing the upstream weights at load instead gives the same transcripts within one layout error, at 4.1 GB on disk and 4.1 GiB peak. Cohere wins long-form by seven words and hears meta-speech v2 deletes, but it is twice as slow on a dictation and six times slower on half a minute of audio. It has no recognition sidecar, so the boosted rows are empty.

v2's 953 MiB peak in the table is its first process, which downloaded the model and paid Core ML's first compile; warm v2 processes peak near 125 MiB.
