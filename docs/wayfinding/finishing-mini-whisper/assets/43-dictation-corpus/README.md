# Dictation corpus

A recordable evaluation corpus for the three stages of a dictation: what the engine hears, what the sidecar biases, and what the polish rewrites. Each stage is a JSONL file of scripts to read aloud; the recordings the user makes against them become a reusable fixture for comparing engines, boost configurations, cleanup prompts, and models — the same voice, the same sentences, forever.

## The stages

**Stage 1 — intelligibility** (`stage1-intelligibility.jsonl`, 25 entries). Pure transcription quality. Harvard list 1 (IEEE 297-1969 — each list is phonetically balanced on its own — phonetically balanced, public domain, the standard instrument for intelligibility across microphones and noise) plus 15 confusable-word sentences where context must pick the homophone: their/there/they're, brake/break, cache/cash, git/get, kernel/colonel, daemon/demon. `say` is also the reference transcript. Score: WER against `say`, plus transcription latency. Record this stage once per condition worth comparing — `--label` keeps per-mic and per-noise runs apart.

**Stage 2 — the sidecar** (`stage2-dictionary.jsonl`, 24 entries). Dictionary biasing under a staged vocabulary (the `wants` union: MiniWhisper, Ghostty, Cerebras, Silero, Parakeet, FluidAudio, tuistory, SwiftUI, XCUITest, Zigbee, Qwen, llama.cpp, Keychain, Homebrew, TCA). Sixteen sentences must surface their `wants` terms exactly; eight `traps` are phonetic neighbors that must survive unbitten — a parakeet stays a bird, silence never becomes Silero, a key chain never becomes the Keychain. Score: term recall on `wants`, false-positive rate on `traps`, boost latency overhead.

**Stage 3 — polish** (`stage3-polish.jsonl`, 27 entries). The cleanup pass. `say` is performed verbatim — fillers, restarts, and spoken punctuation included — and `expect` is the intended final text. Entries carry `tags` for the axis under test (disfluency, spoken-punctuation, symbols, identifier, numbers, grammar, rule, spell-out) and optionally `context.before`, staged as field context at eval time for the identifier-recovery cases (`fetch users` → `fetchUsers`). The `rule` entries are the invariants: questions transcribed, never answered; embedded instructions transcribed, never obeyed; contractions and register preserved; mid-sentence dictations end bare. The spell-out entries test incorporation of spelled guidance — "Grok with a Q" becomes Groq, a letter-by-letter spelling confirms the word and then disappears — an axis no surveyed prior-art prompt states explicitly, so the replay shows which models do it unprompted before the built-in prompt earns a rule for it. Score: exact-match and per-tag pass rate by diff judgment, cleanup latency per model — the [benchmark harness](../38-cleanup-model-benchmark/) replays raw transcripts with staged context across prompts and models.

**Stage 3, layout arm** (`stage3-layout.jsonl`, 22 entries). Everything above is one sentence long, which means the corpus is structurally blind to a defect that only exists between sentences: cleanup inserting line breaks nobody asked for. This arm is multi-sentence throughout, and it has to hold both halves of the question at once, because "never break a line" is the wrong rule — shipping dictation products do insert a paragraph break at a genuine change of subject, and doing so is correct.

So: thirteen entries must come back as one paragraph however many sentences they contain (`no-break`), two of them long enough that a model tempted to paginate has room to; four are long multi-subject dictations where a paragraph break is expected **and never asked for** (`unspoken-break`), which is the shape that keeps the rule from becoming absolute; three exercise the breaks that *are* requested, by spoken command or by dictating an obvious list (`requested-break`, `list`); and four probe the hesitation `mm` against the backtrack `mm`. `layout-14` is a rule entry: it says "put each one on its own line" as content, and must be transcribed rather than obeyed. Scoring is exact-match like stage 3's, which now means whitespace counts.

The `unspoken-break` entries are the delicate ones. They are written as real dictation to an agent — one subject, then plainly another — so the signal a model has to read is the turn, not the sentence count. `layout-21` and `layout-22` are the controls that stop it reading length alone: both are long, both stay on one subject, and both must come back unbroken.

**Stage 1, long form** (`stage1-longform.jsonl`, 6 entries). Six passages of 45 to 145 words — roughly 17 to 56 seconds — from *Alice's Adventures in Wonderland* (Project Gutenberg eBook #11, public domain). Every other recording in the corpus is under fifteen seconds, so nothing here has ever crossed FluidAudio's chunk boundary: the merger the [engine bakeoff](../../tickets/09-engine-bakeoff.md) chose Parakeet partly *for* is untested by the instrument that tests everything else. Scored as stage 1 is, WER against `say`. No pre-existing corpus of long-form *dictation* was found — read-aloud literary prose is the wrong shape for the polish stages and the right shape for this one.

## Recording

```sh
./record.py stage1-intelligibility.jsonl              # default mic
./record.py stage3-layout.jsonl                       # the layout arm
./record.py stage1-longform.jsonl                     # long takes; mind the 15-second boundary
./record.py stage1-intelligibility.jsonl --label usb-mic --device ":1"
ffmpeg -f avfoundation -list_devices true -i ""       # device indices
```

One prompt at a time: Enter records, Enter stops, then keep / redo / play back. WAVs land in `recordings/<stage>[-label]/<id>.wav` at 16 kHz mono — the engine's canonical format — and an existing file marks its entry done, so sessions resume where they stopped. Stage 3's performances matter: read the fillers and the restarts as written, speak "comma" and "dash dash" literally.

Scripts are committed; recordings stay untracked until a set proves worth keeping.

## Field cases

The scripted stages know their answer before the microphone opens. A real dictation does not, and only the person who spoke it can supply one. `adjudicate.py` serves a small local page — the audio with a scrubber, and two editable boxes — and collects two answers into `field-cases.jsonl`: `say`, the verbatim truth of what was spoken, and `expect`, what should have been typed from it. Both boxes arrive prefilled, the engine's raw transcript seeding `say` and the cleanup that shipped seeding `expect`, so a dictation that went right is one click and one that went wrong is an edit.

Adjudicating is listening and typing at the same time — scrub back three seconds, fix a word, scrub back again — which is why it is a page rather than the `$EDITOR` form it started as. `⌥←` and `⌥→` seek without leaving the box being typed in, space plays and pauses anywhere else, `⌘↩` saves and advances. The cleanup that shipped stays on screen underneath, JSON-escaped so the line breaks that caused the complaint are visible as characters rather than as layout. Saving rewrites the file keyed by history id, so revisiting an entry corrects it instead of recording a second opinion about it.

A dictation is chosen, never merely encountered. Most of the log went fine, and walking all of it is an afternoon spent confirming things the corpus already knows, so the tool refuses to run without a selector. `--defect` names a failure and finds the entries exhibiting it: `unrequested-break` catches a transcript cleanup split across lines with no spoken `new line` or `new paragraph` anywhere in the raw, and `surviving-filler` catches a hesitation the engine heard and cleanup was supposed to delete. `--id` takes an entry [`history_triage.py`](history_triage.py) already ranked, by id or a unique prefix. `--match` is the escape hatch for a failure nobody has written a detector for yet, and writing one is a ten-line function beside the other two.

```sh
./adjudicate.py --defect unrequested-break --list   # what it found, and why each entry qualified
./adjudicate.py --defect unrequested-break          # then work through them in the browser
./adjudicate.py --id 3947C08F                       # one entry, by id prefix
./adjudicate.py --match 'sidecar'
```

The audio is copied to `recordings/field-cases/<id>.wav` on the way past, because retention deletes the vault's copy on its own schedule and an adjudicated entry without its recording is an opinion rather than a fixture. Each record keeps its provenance — the history id, the engine, the raw transcript, the cleanup that shipped and the model that wrote it — so a field case can always be read as the failure it was reported as. [`history_triage.py`](history_triage.py) ranks which entries are worth listening to first; this is what turns one of them into corpus.

## Replay and scoring

Recordings are replayed through the real engine, not a re-recording: `asr-replay` is an executable target in `Packages/ASREngine` that loads the same pinned artifact the dev channel downloaded, decodes each WAV, and writes one JSONL line of `{id, transcript, latencyMs, outcome, audioSeconds}` per entry. It calls `transcribeIgnoringGate`, because the gate answers "did the speaker mean to say anything" and a corpus fixture answered that when it was recorded.

```sh
swift build -c release --package-path ../../../../../Packages/ASREngine --product asr-replay
REPLAY=../../../../../Packages/ASREngine/.build/release/asr-replay

$REPLAY --stage stage1-intelligibility.jsonl \
  --recordings recordings/stage1-intelligibility-built-in --output results/built-in/stage1.jsonl

# Stage 2 runs twice: the same audio bare, then with the `wants` union staged as the dictionary.
$REPLAY --stage stage2-dictionary.jsonl \
  --recordings recordings/stage2-dictionary-built-in --output results/built-in/stage2-bare.jsonl
$REPLAY --stage stage2-dictionary.jsonl --boost-from-wants \
  --recordings recordings/stage2-dictionary-built-in --output results/built-in/stage2-boosted.jsonl

$REPLAY --stage stage3-polish.jsonl \
  --recordings recordings/stage3-polish-built-in --output results/built-in/stage3-raw.jsonl
```

`--model-root` points at another channel's artifact; `--vocabulary FILE` stages an arbitrary newline-separated term list instead of the stage's own `wants`; `--minimum-similarity` overrides the boost's similarity floor, which is how [the sweep](results/boost-sweep/) was run.

Other engines reach the same JSONL through two sibling scripts. `transcribe_cohere.py` runs `CohereLabs/cohere-transcribe-03-2026` through `mlx-audio`'s native MLX implementation, loading the model once and excluding a warmup pass so its latency is warm per-utterance like the engine's own; `--no-conversion`, `--4bit`, and `--8bit` choose the runtime precision, and weights live in the Hugging Face cache. `transcribe_whisper.py` drives Homebrew's `whisper-cli` over the same recordings. Its latency is whisper's own reported transcription time with the model already resident, so it excludes the per-invocation spawn and model load a one-shot CLI would pay; `--overhead-report` prints that excluded tax. Model weights live in `~/.cache/whisper.cpp/`, deliberately outside the repo.

`transcribe_hosted.py` reaches the same JSONL through a provider's own transcription API — `--provider groq` (whisper-large-v3-turbo on the OpenAI-shaped endpoint), `elevenlabs` (Scribe v2), or `gemini` (the language model asked to transcribe). Its `latencyMs` is a **network round trip measured from this machine**, not the provider's inference time, and rate-limit waits are excluded from it and reported separately. `--vocabulary-from-wants` stages the stage file's `wants` union through whichever conditioning channel that provider actually has — whisper's decoder `prompt`, Scribe's `keyterms`, Gemini's instructions — which is the fourth arm of [the vocabulary question](results/asr-prompting/). Whisper's prompt is conditioning, not instruction: terms only, exact spelling, comma-separated on one line, because newlines silence the decoder entirely.

```sh
./transcribe_hosted.py --provider elevenlabs --stage stage1-intelligibility.jsonl \
  --recordings recordings/stage1-intelligibility-built-in \
  --output results/elevenlabs-scribe-v2/stage1.jsonl

./transcribe_hosted.py --provider groq --stage stage2-dictionary.jsonl --vocabulary-from-wants \
  --recordings recordings/stage2-dictionary-built-in \
  --output results/asr-prompting/stage2-groq-conditioned.jsonl

./transcribe_whisper.py --stage stage1-intelligibility.jsonl \
  --recordings recordings/stage1-intelligibility-built-in \
  --model ~/.cache/whisper.cpp/ggml-large-v3-turbo.bin \
  --output results/whisper-large-v3-turbo/stage1.jsonl

set -a && source ../../../../../.env && set +a   # HF_TOKEN; the Cohere repo is gated
./transcribe_cohere.py --stage stage1-intelligibility.jsonl \
  --recordings recordings/stage1-intelligibility-built-in \
  --output results/cohere-transcribe/stage1.jsonl
```

`score_corpus.py` scores the two stages that have an ASR score. `--report PATH` persists the full per-entry detail as JSON; it precedes the stage subcommand.

```sh
./score_corpus.py --report results/built-in/stage1-score.json \
  stage1 stage1-intelligibility.jsonl results/built-in/stage1.jsonl

./score_corpus.py --report results/built-in/stage2-score.json stage2 stage2-dictionary.jsonl \
  --bare results/built-in/stage2-bare.jsonl --boosted results/built-in/stage2-boosted.jsonl
```

Stage 2 terms are matched exactly as the corpus writes them, so `keychain` does not satisfy `Keychain`; a case-folded match is reported alongside as its own line, since casing is the only thing separating a bitten trap from an intact one.

`sweep` applies that same stage-2 score to any number of labelled runs at once. A run is any JSONL keyed by corpus id with a `transcript` — an engine's output, a boosted output at some threshold, or a cleanup pass's final text — which is what lets a sidecar arm and a cleanup arm be compared on the text that would actually have been typed.

```sh
./score_corpus.py sweep stage2-dictionary.jsonl \
  --run bare=results/built-in/stage2-bare.jsonl \
  --run boosted=results/built-in/stage2-boosted.jsonl \
  --run bare+gemini=results/dictionary-three-way/stage2-bare-gemini-3.6-flash.jsonl
```

`corpus_cleanup.py` replays stage 3's raw transcripts through the app's own cleanup prompt. It lifts `CleanupPrompt.builtIn` out of the Swift source at run time and assembles the tagged user message the way `CleanupPrompt.userMessage` does, with `context.before` staged as `BEFORE_CARET`; the request body is the app's — model, messages, `stream: false`, no temperature or token cap — so the latency is the latency the pipeline would see. Settings' additional instructions are deliberately not sent: `expect` is written against the built-in rules alone.

```sh
set -a && source ../../../../../.env && set +a   # AIG_APIKEY

./corpus_cleanup.py stage3 stage3-polish.jsonl --raw results/built-in-r2/stage3-raw.jsonl \
  --endpoint https://aig.thurstons.house/v1 --api-key-env AIG_APIKEY \
  --model gpt-5.6-luna --model gemini-3.6-flash --results-dir results/built-in-r2
```

It prints each entry's cleaned text and wall-clock latency, then exact-match rate, a per-tag pass table, and a unified diff for every failure. `--results-dir` writes `stage3-<model>.jsonl` and `stage3-<model>-score.json`, with latency reported twice: the cleanup call alone, and end to end against the ASR latency carried in the raw file. Read the failures with the raw transcript in hand: an entry can fail because the engine never delivered the material the cleanup needed, which is a stage 1 result wearing a stage 3 label.

`--endpoint` and `--api-key-env` are the only things separating one provider from another: the gateway and `https://api.cerebras.ai/v1` take the app's body unchanged. `https://api.anthropic.com/v1` is refused outright as of [round 4](results/prompt-tuning-r4/README.md) — the Anthropic key pays for transcription and nothing else, and Haiku is reachable over the Claude subscription through [`agent-sdk-cleanup/`](agent-sdk-cleanup/README.md) for nothing. `--retries` covers 429 and 5xx, honouring `Retry-After`, and the score file reports throttled seconds separately from latency so a rate limit never contaminates a timing.

Three more flags exist for arms that are not the app's own configuration. `--prompt none` skips the request and scores the raw transcript, which is the control column of an [end-to-end matrix](results/e2e-combos/). `--prompt s1-mini` sends that model's documented control line instead of `CleanupPrompt.builtIn`, because s1-mini has no prompt surface and no dictionary; `--no-api-key` is what a local `llama-server` wants. And the `stage2` subcommand stages the `wants` union as the DICTIONARY block, then writes its cleaned text in `asr-replay`'s own shape so `score_corpus.py sweep` scores it as just another run of transcripts.

```sh
./corpus_cleanup.py stage2 stage2-dictionary.jsonl --raw results/built-in/stage2-bare.jsonl \
  --dictionary-from-wants --endpoint https://aig.thurstons.house/v1 \
  --model gemini-3.6-flash --results-dir results/dictionary-three-way --arm bare
```

`history_triage.py` points the same question at unscripted material. The dev channel's history log and audio vault are the only dictations in this repo nobody wrote a script for, and the only ground truth is the person who spoke them; the script reads both read-only and ranks the entries whose text looks semantically dubious — a cleanup that rewrote most of its transcript, a raw shaped like a gate failure or a decoder loop, a cleanup that dropped a number or added a word nobody said — so a listening pass covers the suspects instead of the corpus. The report is personal by nature and lands outside the tracked asset, at `.build/history-triage.md`.

The [Agent SDK runner](agent-sdk-cleanup/) is a fourth entry point: it imports this harness and swaps only the transport, so Haiku can be measured on the Claude subscription's OAuth session instead of a metered key, with the same prompt, the same scoring, and the same output files.

Everything lands under `results/<label>/`, committed so runs stay comparable. Each run directory carries a README naming its conditions and headline numbers: [`built-in`](results/built-in/) and [`built-in-r2`](results/built-in-r2/) for the incumbent engine; [`cohere-transcribe`](results/cohere-transcribe/), [`whisper-large-v3-turbo`](results/whisper-large-v3-turbo/), [`whisper-medium-en`](results/whisper-medium-en/), [`elevenlabs-scribe-v2`](results/elevenlabs-scribe-v2/), [`groq-whisper-large-v3-turbo`](results/groq-whisper-large-v3-turbo/), and [`gemini-transcribe`](results/gemini-transcribe/) for the alternatives; [`boost-sweep`](results/boost-sweep/) for the sidecar's similarity floor; [`dictionary-three-way`](results/dictionary-three-way/) and [`asr-prompting`](results/asr-prompting/) for where vocabulary is best spent; [`gemini-direct`](results/gemini-direct/) and [`agent-sdk-haiku`](results/agent-sdk-haiku/) for what the transport costs; [`e2e-combos`](results/e2e-combos/) for engine × cleanup as a whole pipeline; and [`prompt-tuning-haiku`](results/prompt-tuning-haiku/) for the prompt search itself, whose `tune.py`, `propose.py`, `ablate.py`, `perturb.py`, `subrates.py`, and `leakcheck.py` import this harness and swap only the prompt source and the concurrency — the last of them re-testing each prompt rule on templated transcripts built over `harvard-sentences.txt`, the public-domain IEEE 297-1969 lists cached whole here, using lists 4-20 because lists 1 to 3 are stage 1's script and the recorded holdout; [`prompt-tuning-r3`](results/prompt-tuning-r3/) for the layout round, which adds `breakrate.py` and `shapes.py` — the first re-judging a run on whitespace alone, since an entry fails exact match identically whether cleanup split it across four lines or merely declined to write `6x` for "six times"; and [`prompt-tuning-r4`](results/prompt-tuning-r4/) for the register round, which adds `layoutrate.py`, the collected prior-art exemplars, and the `--additional-instructions` plumbing that finally sends the harness the same system message the app does; and [`prompt-tuning-r5`](results/prompt-tuning-r5/) for paragraph-at-a-time compression, the 524-word shipped prompt, and the guarded Sol proposer over ChatGPT OAuth. The rollup is [`results/README.md`](results/README.md), and the per-profile answer is [`results/profiles-recommendation.md`](results/profiles-recommendation.md).

## Metrics

Every stage records latency alongside accuracy, so a model or configuration change answers both "is it right" and "what did it cost":

| stage | accuracy                                    | performance                        |
| ----- | ------------------------------------------- | ---------------------------------- |
| 1     | WER vs `say`                                | audio-end → transcript             |
| 2     | `wants` recall, `traps` false positives     | boost overhead vs stage 1 baseline |
| 3     | exact match + per-tag pass rate vs `expect` | request → cleaned text, per model  |

Punctuation-heavy comparisons can borrow Punctuation Error Rate from LibriSpeech-PC (arXiv:2310.02943) rather than letting commas drown in WER.
