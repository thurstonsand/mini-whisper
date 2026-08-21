# Profiles, decided from the measurements

[Ticket 47](../../../tickets/47-cleanup-endpoint-profiles.md) proposes three profiles and names a candidate stack for each, pending round-3 numbers. The numbers are in. This file answers each profile with the stack that wins it, the cells that prove it, and the one place a hosted engine changes the answer.

Every number is from this corpus: one voice, one built-in microphone, 27 stage-3 entries, 25 stage-1, 24 stage-2. Hosted latencies are network round trips from this machine and depend on the connection.

## The short version

| profile                   | engine                   | vocabulary                    | cleanup                   | score     | end to end |
| ------------------------- | ------------------------ | ----------------------------- | ------------------------- | --------- | ---------- |
| speed-to-accuracy, online | Parakeet                 | DICTIONARY block              | gpt-oss-120b (Cerebras)   | 15/27     | **420 ms** |
| best accuracy             | **ElevenLabs Scribe v2** | `keyterms` + DICTIONARY block | gemini-3.6-flash (direct) | **21/27** | 2443 ms    |
| best offline              | Parakeet                 | sidecar                       | s1-mini                   | 12/27     | **107 ms** |

The ticket's guesses survive at both ends and break in the middle: a hosted engine does take the accuracy crown, and it is not one anybody guessed.

## 1. Best speed-to-accuracy online — Parakeet + gpt-oss-120b, unchanged

15/27 at 420 ms end to end, engine included ([e2e-combos](e2e-combos/README.md)). Nothing measured beats it on the axis it exists for. The alternatives and what they cost:

- Scribe v2 + gpt-oss-120b: 16/27 at 950 ms. One entry for 530 ms and a network dependency — a bad trade for a profile named speed.
- Parakeet + haiku 4.5: 17/27 at 696 ms. Two entries for 276 ms, and this is the one genuinely arguable swap. If the profile is "fast enough and noticeably better", it is haiku; if the profile is "the fastest thing that is not embarrassing", it is gpt-oss.
- Groq whisper + anything: strictly worse than the local whisper at the same latency, which is itself worse than Parakeet.

The caveat on gpt-oss-120b is unchanged and it is not a taste caveat. It leaves `period` untranslated twice, appends a period to the mid-sentence dictation the prompt forbids, and writes `GrokQ` for the spell-out. One of those breaks an invariant. **A profile that ships gpt-oss-120b should get its own prompt pass first** ([ticket 48](../../../tickets/48-prompt-eval-automation.md)) — those are instruction-following failures, the kind prompt work fixes.

Vocabulary: DICTIONARY block, sidecar off. Parakeet has no conditioning channel, and the sidecar destroys five of eight trap sentences to recover terms the block recovers anyway. gpt-oss-120b is the weakest reader of the block (15/18, 1 trap) but still beats the sidecar four to one on traps, at +381 ms.

## 2. Best accuracy — Scribe v2 + gemini, and the engine is the news

**21/27 is the best cell this corpus has produced**, two entries clear of the previous best (Parakeet + gemini at 19/27) and three clear of anything else. Scribe v2 is also the most accurate engine measured, at 0.98% stage-1 WER against Parakeet's 1.95% — the first engine to beat the shipping one.

The whole matrix moves with it: Scribe + haiku is 19/27 at 1313 ms, matching Parakeet + gemini's score in two thirds of the time. So the accuracy profile has a real internal choice:

| stack                      | score | end to end |
| -------------------------- | ----- | ---------- |
| Scribe v2 + gemini         | 21/27 | 2443 ms    |
| Scribe v2 + haiku 4.5      | 19/27 | 1313 ms    |
| Parakeet + gemini (direct) | 19/27 | 1914 ms    |

Two entries for 1.1 s. For a profile explicitly named "best accuracy", take the two entries; the haiku variant is what the speed-conscious version of this profile looks like, and it dominates Parakeet + gemini outright.

Run gemini against Google directly, not the gateway: identical 19/27 with an identical failure set, 618 ms faster at the median ([gemini-direct](gemini-direct/)).

Vocabulary: Scribe's `keyterms` reaches 17/18 recall at 2 traps for **+99 ms** — the sidecar's recall class without the sidecar's carnage, and a seventh of haiku's cost ([asr-prompting](asr-prompting/README.md)). Pair it with the DICTIONARY block, which independently reaches 18/18 at 0 traps on gemini. Neither is measured stacked; the block alone is the safe default and the keyterms channel is what makes the engine worth its price beyond raw WER.

### What this costs, and it is not only latency

Scribe is a paid API on somebody else's servers, and every dictation leaves the machine as audio rather than as text. The cleanup profiles already send transcripts out; this sends the recording. That is a different consent, and a profile that changes it should say so at the point of choosing.

### Where the hosted engine is *not* the answer

Scribe + s1-mini is 11/27; Parakeet + s1-mini is 12/27. The best engine in the table loses the offline column, because s1-mini cannot exploit what it delivers — it is given neither the built-in prompt nor a dictionary, so the extra material arrives and goes nowhere. A better engine only pays where a capable cleanup model can spend it.

## 3. Best offline — Parakeet + sidecar + s1-mini, unchanged and uncontested

12/27 at 107 ms, and it is the only stack in the table that runs on a plane. Cohere + s1-mini, the superwhisper-shaped alternative, loses on both axes (9/27 at 172 ms). Nothing hosted competes by definition.

The sidecar stays here and only here. With cleanup that cannot read a dictionary, acoustic biasing is the entire vocabulary story: 16/18 recall against bare Parakeet's 5/18. It costs five of eight trap sentences, which is the price of the profile.

s1-mini's seven-entry gap to gemini is structural, not quality — spell-out 0/3, identifier 0/3, staged context 0/3, all axes its card never mentions and its control line never states. It holds every invariant. That is the correct shape for an offline fallback, and [ticket 48](../../../tickets/48-prompt-eval-automation.md) is where anyone tries to close it.

**The untested hypothesis in [ticket 47](../../../tickets/47-cleanup-endpoint-profiles.md) remains untested**: whether sidecar + s1-mini specifically shore each other up. Round 3 measured sidecar arms and s1-mini arms, never crossed. It is one corpus run.

## A local wrinkle worth one more run

whisper.cpp large-v3-turbo with `--prompt` reaches 12/18 recall and bites **zero traps for +3 ms** — a local, non-destructive vocabulary channel, which is exactly what the offline profile lacks. Its engine accuracy is worse than Parakeet's (3.90% vs 1.95%) and its e2e cells are worse, so it does not win the profile as it stands. But "Parakeet + sidecar" is offline vocabulary at the cost of five sentences, and "whisper + prompt" is offline vocabulary at the cost of none, and no run has yet crossed whisper + prompt with s1-mini to see which stack the trade favours.

## What no longer needs shopping

Three entries fail in every cell of the matrix under every model, and they are not model problems:

- `polish-15` — nothing infers `usr` from "slash user". Either the prompt learns the convention or `expect` changes.
- `polish-20`, `polish-22`, `polish-30` — the number word, the lowercase `p.m.`, the leading capital on a bare mid-sentence ending. Prompt work, not model work.
- `polish-11` — now purely an expectation defect. Every engine except Parakeet hears the quote/unquote, and every capable model then writes `She said, "It ships tonight."` where `expect` demands `She said "it ships tonight."`. The entry is scoring a comma.

These are [ticket 48](../../../tickets/48-prompt-eval-automation.md)'s inputs, per profile, one stack at a time.
