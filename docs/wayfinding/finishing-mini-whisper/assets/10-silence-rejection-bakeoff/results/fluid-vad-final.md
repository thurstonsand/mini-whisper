# FluidAudio VAD recalibration aggregate results

Only aggregates are published. Private audio, probabilities, transcripts, and fixture-level decisions are omitted.

Selected on calibration: threshold `0.9`, minimum speech `150 ms`.

| Split | Fixtures | False accepts | False rejects |
| --- | ---: | ---: | ---: |
| calibration | 14 | 0 | 0 |
| holdout | 20 | 0 | 0 |

| Threshold | Minimum speech | Calibration FA / FR | Holdout FA / FR |
| ---: | ---: | ---: | ---: |
| 0.35 | 0 ms | 1 / 0 | 1 / 0 |
| 0.35 | 150 ms | 1 / 0 | 1 / 0 |
| 0.35 | 250 ms | 1 / 0 | 1 / 0 |
| 0.35 | 500 ms | 1 / 0 | 1 / 0 |
| 0.40 | 0 ms | 1 / 0 | 1 / 0 |
| 0.40 | 150 ms | 1 / 0 | 1 / 0 |
| 0.40 | 250 ms | 1 / 0 | 1 / 0 |
| 0.40 | 500 ms | 0 / 0 | 1 / 0 |
| 0.45 | 0 ms | 0 / 0 | 1 / 0 |
| 0.45 | 150 ms | 0 / 0 | 1 / 0 |
| 0.45 | 250 ms | 0 / 0 | 1 / 0 |
| 0.45 | 500 ms | 0 / 0 | 1 / 0 |
| 0.50 | 0 ms | 0 / 0 | 0 / 0 |
| 0.50 | 150 ms | 0 / 0 | 0 / 0 |
| 0.50 | 250 ms | 0 / 0 | 0 / 0 |
| 0.50 | 500 ms | 0 / 0 | 0 / 0 |
| 0.55 | 0 ms | 0 / 0 | 0 / 0 |
| 0.55 | 150 ms | 0 / 0 | 0 / 0 |
| 0.55 | 250 ms | 0 / 0 | 0 / 0 |
| 0.55 | 500 ms | 0 / 0 | 0 / 0 |
| 0.65 | 0 ms | 0 / 0 | 0 / 0 |
| 0.65 | 150 ms | 0 / 0 | 0 / 0 |
| 0.65 | 250 ms | 0 / 0 | 0 / 0 |
| 0.65 | 500 ms | 0 / 0 | 0 / 0 |
| 0.75 | 0 ms | 0 / 0 | 0 / 0 |
| 0.75 | 150 ms | 0 / 0 | 0 / 0 |
| 0.75 | 250 ms | 0 / 0 | 0 / 0 |
| 0.75 | 500 ms | 0 / 0 | 0 / 0 |
| 0.85 | 0 ms | 0 / 0 | 0 / 0 |
| 0.85 | 150 ms | 0 / 0 | 0 / 0 |
| 0.85 | 250 ms | 0 / 0 | 0 / 0 |
| 0.85 | 500 ms | 0 / 0 | 0 / 0 |
| 0.90 | 0 ms | 0 / 0 | 0 / 0 |
| 0.90 | 150 ms | 0 / 0 | 0 / 0 |
| 0.90 | 250 ms | 0 / 0 | 0 / 0 |
| 0.90 | 500 ms | 0 / 0 | 0 / 0 |

- Warm wall VAD median: `13.782 ms` (15 ms budget: **PASS**).
- Model-reported median: `13.502 ms`; cold/maximum wall: `150.540 ms`.
- Exact gate framing: `4096` samples (`256 ms`) with app-side zero padding before one whole-utterance call.
- Pinned VAD: `FluidInference/silero-vad-coreml@b419383c55c110e2c9271fa6ee0ea83d03c70d96`.
- Pinned ASR: `FluidInference/parakeet-tdt-0.6b-v2-coreml@ee09c569f73759e6d44c9bd16766f477b2b36d39`.
- Synthetic no-speech fixtures: `0` accepted / `5` total.
- Accepted original audio reaches `AsrManager` unchanged; padding exists only in the gate copy.

## Acceptance

- PASS — all model chunks exact
- PASS — synthetic no speech rejected
- PASS — vad below fifteen ms budget
- PASS — zero false accepts and rejects both splits
