# FluidAudio v0.15.5, Parakeet v3

The same recordings as the incumbent, replayed through a disposable SwiftPM release harness. This is an ASR-only comparison for ticket 53, with no dictionary, CTC helper, silence gate, streaming, or cleanup. All 97 entries completed: 96 nonempty transcripts and one `engineEmpty` on `polish-30`. Inference ran after the Voz coordinator's explicit clearance, with no concurrent Voz benchmark.

## Headline

| stage | accuracy | warm median / max |
| ----- | -------- | ----------------- |
| Intelligibility, 25 entries | **2.93% WER**, 6S 0D 0I / 205 words; 19/25 clean | **55.4 / 58.1 ms** |
| Longform, 6 entries | **13.05% WER**, 9S 36D 29I / 567 words; 0/6 clean | **131.3 / 187.5 ms** |
| Dictionary bare, 24 entries | **3/18 exact wants**, 0/8 exact traps | **56.3 / 64.6 ms** |
| Dictionary holdout bare, 15 entries | **2/10 exact wants**, 0/6 exact traps | **56.5 / 60.5 ms** |
| Polish raw, 27 entries | ASR input to cleanup, not a cleanup score | **57.8 / 99.2 ms** |

Case-folding changes dictionary recall to 6/18 and traps to 2/8; holdout recall to 5/10 and traps to 1/6. These are substring matches under the corpus scorer, not independent judgments of a false recognition.

The incumbent v2 has 1.95% intelligibility WER at 55 ms, 5/18 bare dictionary recall, and 5/10 bare holdout recall with zero exact traps in either dictionary set. Its [existing longform run](../prompt-tuning-r3/stage1-longform-score.json) has 8.11% WER at 119.1 ms. V3 does not improve this corpus at the selected configuration. The dictionary comparison JSON files score both incumbent and v3 with the same current scorer; incumbent timing is historical, not a new serial rerun.

### Longform loss

Some longform errors are defects in the reference: recordings speak `quote`, `end quote`, and `parentheses`, while `say` contains typographic punctuation. The scorer also separates curly apostrophes but preserves straight ones, so `wouldn’t` versus `wouldn't` incurs word errors. These affect the incumbent too, and the published score deliberately uses the unchanged corpus.

There is also a substantive v3 omission. On the 35.798-second `longform-02`, it jumps from `a very deep well` to `Why I wouldn't say anything about it`, losing the passage beginning `Well, thought Alice to herself` through `How brave they'll all think me at home`. The incumbent transcript retains it. V3 has 29 deletions on this entry versus the incumbent's 3. This is a longform failure under the default mel-context configuration, not merely punctuation normalization. No no-mel or dual-decode tuning was tried, and this run does not establish which internal component dropped the passage.

Intelligibility's six substitutions are steady→study, brake→break, site→sight, colonel→kernel, daemon→demon, and heir→air. Stage 3 raw output is retained for later cleanup replay; no polish quality claim follows from it. `polish-30`, the 1.990-second deliberately unfinished `and then we could maybe`, returns an empty string. Cleanup cannot preserve an unfinished phrase the ASR discarded.

## Runtime and model identity

- FluidAudio **v0.15.5**, revision **`19600a485baa4998812e4654b70d2bab8f2c9949`**, resolved from its GitHub URL by SwiftPM. The existing bakeoff clone's packed tag ref maps `v0.15.5` directly to this commit; `Package.resolved` records the same revision.
- Model **`FluidInference/parakeet-tdt-0.6b-v3-coreml`**, snapshot **`aed02740059203c4a87495924f685de3722ae9ce`**. Int8 encoder; `Preprocessor.mlmodelc`, `Encoder.mlmodelc`, `Decoder.mlmodelc`, `JointDecisionv3.mlmodelc`, and `parakeet_vocab.json`.
- **483,105,645 bytes** across 21 constituent files. [model-manifest.json](model-manifest.json) records every file's byte size and SHA-256. All 21 hashes match both the pinned Hugging Face snapshot and the prior bakeoff's committed v3 hash list.
- Backend: FluidAudio's Core ML defaults, CPU-only preprocessor and CPU/Neural Engine for the other models. `ASRConfig(parallelChunkConcurrency: 4, streamingEnabled: false, melChunkContext: true, dualDecodeArbitration: false)` matches the prior bakeoff's default arm. All other decoding options retain this revision's defaults.
- Measured 2026-09-09 on Mac16,8, Apple M4 Pro, 14 physical cores, 48 GiB RAM; macOS 26.5.2 / 25F84, Xcode 26.6 / 17F113, Swift 6.3.3, arm64 macOS 26.0 target. [environment.json](environment.json) retains the command output and resolved dependency.

FluidAudio's `AsrModels.load(from:)` uses the argument's parent plus `Repo.folderName`, which strips `-coreml`. The command supplied the bakeoff's `parakeet-tdt-0.6b-v3-coreml` link, but the runtime loaded the existing sibling **`parakeet-tdt-0.6b-v3/`**. Every consumed file in that sibling was hash-checked against the pinned snapshot; the two extra JSON files in the sibling are not requested by this v3 path. `verify_models.py` verifies this effective directory rather than trusting the argument's spelling. No artifact download was needed.

## Timing and memory contract

The harness decodes every recording to float32 16 kHz mono samples before model loading or transcription timing. It loads one model instance for all five stages, performs one excluded warmup on `harvard-01-01`, then times each call from fresh decoder-state construction through final `result.text`. File reads, JSON output, model load, and warmup are excluded from `latencyMs`. Each output line has exactly `{id, transcript, latencyMs, outcome, audioSeconds}`, with the same rounding as ASRReplay. An inference error aborts rather than silently omitting an entry.

The replay process's first load took **14,743.7 ms**, its excluded warmup **69.3 ms**, and its peak RSS **540.7 MiB** / 566,951,936 bytes. The high-water mark was already reached after model loading. A separate load-only process immediately afterward loaded in **133.1 ms**, reaching **38.3 MiB** / 40,206,336 bytes, but performed no transcription. Do not compare the latter RSS to an inference-process peak. `/usr/bin/time -l` independently agrees with the replay's `getrusage` RSS and reports 21.27 seconds total process wall time.

These are first-process versus immediately repeated load measurements, not fresh-install cold start: models were already downloaded, and existing Core ML/OS caches were not cleared. The earlier bakeoff's roughly 213-second initial specialization is not remeasured here. RSS does not fully account for ANE/Core ML allocations. One measured pass gives useful latency evidence but not a thermal or repeated-run variance study.

The final harness additionally sets `ModelHub.offlineMode = true` before loading, preventing any future missing-artifact download or cache purge. This guard was added and release-built after the measured run; the run itself used complete existing artifacts and the same inference code. No inference rerun followed this guard-only change.

## Files and reproduction

- `stage1.jsonl`, `stage1-longform.jsonl`, `stage2-bare.jsonl`, `stage2-holdout-bare.jsonl`, `stage3-raw.jsonl`: raw transcripts and timings.
- `*-score.json`: full scorer detail. Stage 2 uses `sweep` with one `bare` arm, not a fabricated boosted run. `*-comparison-score.json` additionally includes the incumbent bare results.
- `runtime.json`, `reload.json`, `replay.log`, `reload.log`: load, warmup, RSS, and process evidence. `validation.json` confirms all stage IDs in order, exact JSONL fields, and the one empty outcome.
- [Harness](../../../53-voz-engine-spike/fluid/): release source, dependency lock, build log, and effective-path hash verifier.

From the repository root, with the existing bakeoff artifacts present:

```sh
ASSETS=docs/wayfinding/finishing-mini-whisper/assets
HARNESS=$ASSETS/53-voz-engine-spike/fluid
CORPUS=$ASSETS/43-dictation-corpus
OUT=$CORPUS/results/fluid-parakeet-v3
MODEL=$ASSETS/09-engine-bakeoff/.artifacts/fluid-models/parakeet-tdt-0.6b-v3-coreml

python3 "$HARNESS/verify_models.py" "$MODEL" "$OUT/model-manifest.json"
swift build -c release --package-path "$HARNESS"
# Arrange exclusive benchmark timing before these two commands.
/usr/bin/time -l "$HARNESS/.build/release/FluidReplay" replay "$MODEL" "$CORPUS" "$OUT" \
  > "$OUT/replay.log" 2>&1
"$HARNESS/.build/release/FluidReplay" load-only "$MODEL" "$CORPUS" "$OUT" \
  > "$OUT/reload.log" 2>&1

python3 "$CORPUS/score_corpus.py" --report "$OUT/stage1-score.json" \
  stage1 "$CORPUS/stage1-intelligibility.jsonl" "$OUT/stage1.jsonl"
python3 "$CORPUS/score_corpus.py" --report "$OUT/stage1-longform-score.json" \
  stage1 "$CORPUS/stage1-longform.jsonl" "$OUT/stage1-longform.jsonl"
python3 "$CORPUS/score_corpus.py" --report "$OUT/stage2-bare-score.json" \
  sweep "$CORPUS/stage2-dictionary.jsonl" --run "bare=$OUT/stage2-bare.jsonl"
python3 "$CORPUS/score_corpus.py" --report "$OUT/stage2-holdout-bare-score.json" \
  sweep "$CORPUS/stage2-holdout.jsonl" --run "bare=$OUT/stage2-holdout-bare.jsonl"
```

Longform explicitly reads `recordings/stage1-longform/`, not a `-built-in` directory. All four other stages use their `*-built-in` recording directories. Audio totals are 83.991, 216.661, 83.209, 54.655, and 136.034 seconds in replay order.

For a fresh artifact installation, fetch only the five named artifact trees/files at the pinned Hugging Face revision, place their contents beneath a parent directory's `parakeet-tdt-0.6b-v3/`, and pass that directory as `MODEL`. Verify the manifest before replay. The older setup script documents the snapshot download but also imports private fixtures and writes outside this ticket's directories, so this arm did not invoke it.
