# Silence rejection bakeoff aggregate results

Only aggregates and conclusions are published. Private WAVs, transcripts, frame probabilities, timelines, and per-fixture decisions remain local and gitignored.

Selected on calibration: Silero threshold `0.35`, minimum speech `250 ms`.

| Split | Fixtures | False accepts | False rejects | Final nonempty no-speech transcripts | Skipped decodes | Empty speech transcripts |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| calibration | 14 | 0 | 0 | 0 | 6 | 1 |
| holdout | 20 | 0 | 0 | 0 | 8 | 1 |

| RMS baseline | Threshold | Calibration FA / FR | Holdout FA / FR |
| --- | ---: | ---: | ---: |
| whole | 0.001 | 3 / 1 | 5 / 0 |
| framed | 0.001 | 6 / 0 | 6 / 0 |

- Median VAD runtime: `10.1 ms`.
- Median decoder runtime: `59.7 ms`.
- Irregular-buffer probability delta: `0.0`.
- MVP onset clipping: `0 ms`.
- Future endpoint confirmation: `186 ms` median, `376 ms` maximum.

## Conclusions

- Select Silero v6.2 at threshold 0.35 and minimum speech 250 ms.
- Pass accepted utterances to FluidAudio unchanged; the gate does not trim, chunk, or stitch.
- RMS baselines do not satisfy the speech/no-speech acceptance bar.
- Two accepted short-word speech fixtures produced empty Parakeet transcripts.
