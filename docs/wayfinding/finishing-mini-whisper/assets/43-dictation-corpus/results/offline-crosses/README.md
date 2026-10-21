# Offline crosses — the two arms round 3 never ran

[profiles-recommendation.md](../profiles-recommendation.md) closes with two open questions, both about the offline profile, and both unanswerable from round 3 because that round measured sidecar arms and s1-mini arms and never crossed them:

1. Do **sidecar + s1-mini** shore each other up — does a cleanup pass that cannot read a dictionary nevertheless repair what acoustic biasing broke, or does biasing feed it material it can finally use?
2. Does **whisper `--prompt` + s1-mini** beat Parakeet + sidecar + s1-mini? Decoder conditioning is the only offline vocabulary channel measured that bites zero traps, and no run had crossed it with the offline cleanup model.

Everything here is local: `asr-replay` against the pinned Parakeet artifact, `whisper-cli` against `~/.cache/whisper.cpp/ggml-large-v3-turbo.bin`, and `llama-server -hf superwhisper/s1-mini-GGUF:Q4_K_M` on `localhost:8317`. No hosted call was made, so **stage 3 is scored on exact match against `expect` alone** — the deterministic metric this harness has always used; there is no LLM judge in this directory and none was needed.

```sh
# Arm 1 ASR: the stage-2 wants union staged as the sidecar dictionary over stage-3 audio
$REPLAY --stage stage3-polish.jsonl --recordings recordings/stage3-polish-built-in \
  --vocabulary results/offline-crosses/stage2-wants.txt \
  --output results/offline-crosses/stage3-parakeet-boosted-raw.jsonl

# Arm 2 ASR: the same fifteen terms as whisper's decoder prompt, space-separated as in asr-prompting
./transcribe_whisper.py --stage stage3-polish.jsonl --recordings recordings/stage3-polish-built-in \
  --model ~/.cache/whisper.cpp/ggml-large-v3-turbo.bin \
  --flag=--prompt --flag="MiniWhisper Ghostty Cerebras Silero Parakeet FluidAudio tuistory \
SwiftUI XCUITest Zigbee Qwen llama.cpp Keychain Homebrew TCA" \
  --output results/offline-crosses/stage3-whisper-prompted-raw.jsonl

# Cleanup, both arms and both controls
./corpus_cleanup.py stage3 stage3-polish.jsonl --raw <raw> --prompt s1-mini --no-api-key \
  --endpoint http://localhost:8317/v1 --model s1-mini --results-dir results/offline-crosses
./corpus_cleanup.py stage2 stage2-dictionary.jsonl --raw <raw> --prompt s1-mini --no-api-key \
  --endpoint http://localhost:8317/v1 --model s1-mini --results-dir results/offline-crosses --arm <arm>

./score_corpus.py --report results/offline-crosses/stage2-score.json sweep stage2-dictionary.jsonl \
  --run parakeet-sidecar+s1mini=... --run whisper-prompted+s1mini=... (eight runs)
```

Stage-2 ASR inputs are the committed ones — [`built-in/stage2-boosted.jsonl`](../built-in/stage2-boosted.jsonl) and [`asr-prompting/stage2-whisper-turbo-bare.jsonl`](../asr-prompting/). The prompted whisper arm was re-run here anyway and came back **byte-identical to [`asr-prompting/stage2-whisper-turbo-prompted.jsonl`](../asr-prompting/stage2-whisper-turbo-prompted.jsonl)** across all 24 entries, which is the provenance check that the prompt string above is the one that produced the 12/18.

## The baseline moved before either arm ran

Parakeet bare + s1-mini is recorded as 12/27 in [e2e-combos](../e2e-combos/README.md). Re-run today against the current corpus it is **14/27** — and its cleaned text is identical to the committed run on all 27 entries. The two entries are `polish-01` and `polish-22`, the expectations [prompt-tuning-haiku](../prompt-tuning-haiku/) amended, exactly as the results README warns. s1-mini is bit-stable; the ruler changed.

**So the offline profile's real number is 14/27, not 12/27**, and every comparison below is against controls re-run in this session rather than against the published cell.

## Stage 3 — polish (exact match /27)

| stack                              | exact     | ASR median | e2e median | vs its own bare |
| ---------------------------------- | --------- | ---------- | ---------- | --------------- |
| **Parakeet + sidecar + s1-mini**   | **14/27** | 176 ms     | 229 ms     | **±0**          |
| Parakeet bare + s1-mini (control)  | **14/27** | 55 ms      | **106 ms** | —               |
| **whisper + `--prompt` + s1-mini** | 12/27     | 516 ms     | 564 ms     | −1              |
| whisper bare + s1-mini (control)   | 13/27     | 498 ms     | 550 ms     | —               |

**The sidecar's stage-3 transcripts are character-for-character identical to bare Parakeet's, all 27 of them.** Stage-3 audio contains none of the fifteen terms, so the boost has nothing to bias toward and it biases nothing — it just costs. A quiet re-measure with no other process resident puts that cost at **+107 ms** (169.5 ms boosted against 62.9 ms bare, same 27 files, same transcripts); the 176 ms in the table is the run that fed the cleanup pass, taken while `llama-server` was resident.

Whisper's prompt is not inert on stage 3, and it is not helpful. It changes 12 of 27 raws and loses one entry net: `polish-27` converts (the conditioned decoder hears "the store close" where the bare one hears "this door close"), while `polish-10` and `polish-22` break — `fail fast: recover later` for the semicolon, `3:30pm` for `3:30 p.m.`. Those are conditioning artifacts on punctuation and formatting, not vocabulary, which is the risk of a channel that works by imitation rather than instruction.

Per-tag, all four arms are the same shape, and it is the shape [e2e-combos](../e2e-combos/README.md) already described: spell-out 0/3, identifier 0/3, staged context 0/3, invariants held (rule 4/5, and 3/5 on whisper bare). Nothing in either vocabulary channel touches the axes s1-mini structurally lacks.

## Stage 2 — the dictionary (recall /18, traps /8)

Eight runs, one sweep, scored on the final text in each case:

| arm                                | wants recall    | traps bitten  | median     |
| ---------------------------------- | --------------- | ------------- | ---------- |
| Parakeet bare                      | 5/18 27.8%      | 0/8           | 55 ms      |
| Parakeet bare + s1-mini            | 5/18 27.8%      | 0/8           | 108 ms     |
| Parakeet + sidecar                 | 16/18 88.9%     | 5/8 62.5%     | 154 ms     |
| **Parakeet + sidecar + s1-mini**   | **16/18 88.9%** | **4/8 50.0%** | **206 ms** |
| whisper bare                       | 7/18 38.9%      | 0/8           | 483 ms     |
| whisper bare + s1-mini             | 8/18 44.4%      | 0/8           | 535 ms     |
| whisper + `--prompt`               | 12/18 66.7%     | 0/8           | 500 ms     |
| **whisper + `--prompt` + s1-mini** | 12/18 66.7%     | **0/8 0.0%**  | 554 ms     |

s1-mini repairs exactly one bitten trap, and it repairs it by accident: `A Parakeet chattered in the pet shop window` comes back as `A parakeet chattered in the pet shop window.` — the normalizer lowercasing a mid-sentence capital it had no reason to keep, not a model recognizing that a bird is not a model. The other four bitten traps (`Ghostty`, `Cerebras`, `MiniWhisper`, `Keychain`) survive cleanup untouched, because they read as fluent English and nothing downstream can tell they are wrong. That is the irreversibility [asr-prompting](../asr-prompting/README.md) named, measured with the offline cleanup model behind it.

The recall side is flat: s1-mini recovers **zero** terms from either bare arm on Parakeet, and one on whisper (`homebrew` → `Homebrew`, a capitalization, not a recovery). It has no dictionary and it is not being given one, so there is nothing else it could have done.

## Verdicts

**1. Sidecar + s1-mini do not shore each other up.** On stage 3 the pairing is exactly its own control — 14/27 either way, identical text, +107 ms for nothing, because stage-3 audio has no vocabulary to bias. On stage 2 the sidecar's contribution is unchanged by cleanup (16/18) and its damage is very nearly unchanged too: five bitten traps in, four out, and the one that came out did so through a lowercase, not through judgment. The hypothesis is answered and it is answered no. The sidecar's case is what it always was — 16/18 against bare Parakeet's 5/18 when there is no other channel — and s1-mini neither adds to it nor subtracts from it.

**2. whisper + `--prompt` + s1-mini does not beat the Parakeet stack.** It is behind on stage 3 (12/27 vs 14/27), behind on stage 2 recall (12/18 vs 16/18), and behind on latency by a factor of five (554 ms vs 206 ms, and 564 ms vs 229 ms end to end, with whisper's numbers already excluding its per-invocation spawn and model load). What it wins is the only thing it was ever going to win: **0/8 traps against 4/8**, four sentences the Parakeet stack destroys and this one leaves alone.

So the offline profile stays Parakeet + s1-mini, and the open question resolves into a smaller and sharper one: the sidecar earns its place only if 16/18 recall is worth four ruined sentences in eight, since it demonstrably buys nothing on the polish stage and its errors survive the only cleanup model the profile can run. Turning it off costs eleven terms of recall and costs nothing else measured — no stage-3 entry, and −98 ms on stage 2. That is a vocabulary decision now, not a stack decision.

## Caveats

- One voice, one microphone, 27 stage-3 entries, 24 stage-2, 8 traps. "0/8" is still not "zero".
- `llama-server` build 10470 (`0.1.1-dev`), Q4_K_M, `--temp 0`, `enable_thinking=false`. s1-mini reproduced its committed run exactly, so the model is stable across the two sessions; the corpus was not.
- The stage-3 ASR latencies in the table were measured with `llama-server` resident. The +107 ms sidecar figure is the quiet one, and it is the one to quote.
- Whisper's latency excludes spawn and model load, per [its README](../whisper-large-v3-turbo/); the measured tax here was a 515 ms median on top of every entry.

## Files

`stage2-wants.txt` — the fifteen-term union, as staged.
`stage3-parakeet-boosted-raw.jsonl`, `stage3-whisper-prompted-raw.jsonl` — the two new ASR arms.
`stage2-whisper-prompted-raw.jsonl` — the reproduction of the asr-prompting arm.
`stage3-{parakeet-boosted,whisper-prompted,control-parakeet-bare,control-whisper-bare}-s1-mini{,-score}.jsonl/json` — cleanup and per-entry scores.
`stage2-{parakeet-sidecar,whisper-prompted,parakeet-bare,whisper-bare}-s1-mini.jsonl` — cleaned stage-2 text in `asr-replay`'s shape.
`stage2-score.json` — the eight-run sweep.
