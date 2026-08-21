# Vocabulary at the engine — the fourth arm

[dictionary-three-way](../dictionary-three-way/README.md) asked where a vocabulary should be spent and found two answers: in the sidecar before the transcript exists, or in the DICTIONARY block after it exists. There is a third place, and Parakeet does not have it — **the engine's own conditioning channel**. Every hosted engine here has one, and they are not the same mechanism:

| engine                      | channel               | what it is                                                                                                                                  |
| --------------------------- | --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| whisper (Groq, whisper.cpp) | `prompt` / `--prompt` | decoder conditioning: text pretended to precede the audio, 224 tokens, last ones weighing most. Whisper does not follow it, it imitates it. |
| ElevenLabs Scribe v2        | `keyterms`            | a real biasing list, up to 1000 terms; a paid add-on                                                                                        |
| Gemini 3.6 Flash            | instructions          | actual instructions, because the transcriber is a language model                                                                            |

The same fifteen-term `wants` union, the same stage-2 audio, scored the same way as every other arm: recall on `wants`, false positives on `traps`, on the final text.

```sh
./transcribe_hosted.py --provider groq --stage stage2-dictionary.jsonl --vocabulary-from-wants \
  --recordings recordings/stage2-dictionary-built-in --output results/asr-prompting/stage2-groq-conditioned.jsonl

./transcribe_whisper.py --stage stage2-dictionary.jsonl --recordings recordings/stage2-dictionary-built-in \
  --model ~/.cache/whisper.cpp/ggml-large-v3-turbo.bin --flag=--prompt --flag="MiniWhisper Ghostty ..." \
  --output results/asr-prompting/stage2-whisper-turbo-prompted.jsonl

./score_corpus.py --report results/asr-prompting/asr-prompting-score.json sweep stage2-dictionary.jsonl \
  --run parakeet-sidecar=... --run groq-prompted=... --run elevenlabs-keyterms=... (etc.)
```

## The arms

| arm                                | wants recall     | traps bitten  | median  | vs its own bare |
| ---------------------------------- | ---------------- | ------------- | ------- | --------------- |
| Parakeet bare                      | 5/18 27.8%       | 0/8 0.0%      | 56 ms   | —               |
| Parakeet + sidecar                 | 16/18 88.9%      | **5/8 62.5%** | 154 ms  | +98 ms          |
| Groq whisper bare                  | 7/18 38.9%       | 0/8 0.0%      | 478 ms  | —               |
| **Groq whisper + `prompt`**        | 11/18 61.1%      | **0/8 0.0%**  | 524 ms  | +46 ms          |
| whisper.cpp local bare             | 7/18 38.9%       | 0/8 0.0%      | 483 ms  | —               |
| **whisper.cpp local + `--prompt`** | 12/18 66.7%      | **0/8 0.0%**  | 486 ms  | +3 ms           |
| Scribe v2 bare                     | 7/18 38.9%       | 0/8 0.0%      | 531 ms  | —               |
| **Scribe v2 + `keyterms`**         | **17/18 94.4%**  | 2/8 25.0%     | 630 ms  | +99 ms          |
| Gemini bare                        | 9/18 50.0%       | 0/8 0.0%      | 2446 ms | —               |
| Gemini + instructions              | **18/18 100.0%** | 4/8 50.0%     | 2265 ms | −181 ms         |

For comparison, the best arms from [dictionary-three-way](../dictionary-three-way/README.md), all on Parakeet: bare + gemini 18/18 at 0 traps and +1954 ms; bare + haiku 17/18 at 2 traps and +671 ms; bare + gpt-oss-120b 15/18 at 1 trap and +381 ms.

## Decoder conditioning does not share the sidecar's failure mode

This is the finding. The documented risk with whisper's prompt is hallucination — the model reciting terms it was shown. **It did not happen once.** Both whisper arms bite zero traps while raising recall by four to five terms, and the trap sentences are precisely the ones designed to catch it: prompted whisper still writes `A parakeet chattered in the pet shop window`, `A ghostly draft moved through the stairwell`, `She answered with a mini whisper of her own`. The sidecar, given the same fifteen terms, destroys five of those eight sentences.

The difference is what each mechanism sees. The sidecar works on acoustics alone and cannot know that "ghostly" is a word in a sentence about a stairwell. Whisper's prompt enters the same decoder that is already conditioning on the sentence, so a term wins only where the audio and the context both allow it. The sidecar's errors are permanent — laundered into fluent text that no later pass can detect — and whisper's are simply absent.

The cost is that whisper's prompt is weaker: 61–67% recall against the sidecar's 89%. It recovers `MiniWhisper`, `Parakeet`, `Silero`, `Qwen`, `XCUITest`, `Zigbee`, `SwiftUI`, `TCA` and still misses `Ghostty`, `Cerebras`, `Keychain`, `tuistory` — the terms whose audio is genuinely an ordinary English word. That is the correct thing to miss.

Scribe's `keyterms` sits at the other end: 17/18 recall for 2 traps (`Keychain` and `MiniWhisper` — the two terms that are also ordinary phrases), which is the same recall-and-traps point as bare + haiku 4.5, at **+99 ms instead of +671 ms**. Gemini's instructions get everything and bite half the traps, which is what happens when the biasing channel is a model that will do what it is told.

## Where the vocabulary belongs

Three shapes, and the profile decides:

- **Zero-trap tolerance, cleanup on.** DICTIONARY block, gemini: 18/18, 0 traps, ~2 s. Still the only perfect arm.
- **Zero-trap tolerance, latency budget.** Whisper-family engine + `prompt`: 12/18 for +3 ms local, and nothing destroyed. Weaker than any LLM arm, cheaper than all of them, and safe.
- **Recall first.** Scribe + `keyterms`: 17/18 for +99 ms and two traps — the sidecar's recall class without the sidecar's carnage, and a seventh of haiku's latency.

The one thing that is now clearly wrong is the sidecar. It is the only mechanism measured that trades a majority of the trap sentences for its recall, and it is the only one whose errors are irreversible. Its remaining case is unchanged from [dictionary-three-way](../dictionary-three-way/README.md): Parakeet with cleanup off, where there is no other channel — because Parakeet has no prompt.

**That asymmetry is the profile-relevant fact.** The shipping engine is the only engine in this table with no conditioning surface of its own, so on Parakeet the vocabulary must be spent either acoustically (destructive) or in the LLM (slow). Every hosted alternative offers a third option that Parakeet cannot.

## Operational note: whisper's prompt format is load-bearing

The first Groq run sent the fifteen terms newline-separated, one per line. **All 24 entries came back with an empty transcript** — the decoder read the newlines as the end of the utterance and emitted nothing. Comma-separated on one line produced the 11/18 result above; whisper.cpp locally took a space-separated list without complaint. The harness now joins with `", "` and says why.

## Caveats

- Twenty-four entries, eight traps, one voice. "0/8" is not "zero".
- `keyterms` is a metered add-on on ElevenLabs; the latency above includes it, the pricing does not appear anywhere in this corpus.
- Groq's free tier throttled the conditioned run for 72 s; none of that entered a latency.
- The conditioned Gemini arm is faster than its own bare arm. That is the model choosing to think less when it has been told what to expect, not a mechanism worth trusting to repeat.
