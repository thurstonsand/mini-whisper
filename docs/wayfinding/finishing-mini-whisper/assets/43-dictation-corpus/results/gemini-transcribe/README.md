# Gemini 3.6 Flash as the engine, built-in microphone

The dark horse: the same model that wins the cleanup column, asked to do the transcription instead. `POST https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent` with the WAV inline as base64 `audio/wav` and one instruction — transcribe verbatim, keep fillers and false starts, spell out spoken punctuation as the speaker said it, output only the transcript. Default sampling, thinking left on, because that is what the endpoint does unasked.

**Every latency here is a network round trip measured from this machine**, and it includes whatever thinking the model chose to do.

| file                | what it is                                      |
| ------------------- | ----------------------------------------------- |
| `stage1.jsonl`      | raw engine output                               |
| `stage1-score.json` | WER detail, per entry                           |
| `stage3-raw.jsonl`  | the transcripts the cleanup matrix is scored on |

Produced by `./transcribe_hosted.py --provider gemini --stage <jsonl> --recordings <dir> --output <out.jsonl>`.

## Headline

| stage | result                                                                                                    |
| ----- | --------------------------------------------------------------------------------------------------------- |
| 1     | WER **4.39%** (9S 0D 0I over 205 words), 17/25 entries clean, 2339 ms median / 2701 ms mean / 9740 ms max |

**Last place on both axes.** It is the least accurate engine in the table and forty times slower than Parakeet. A language model asked to transcribe is a language model paraphrasing: `glue the sheet` becomes `glued the sheets`, `chopped corn` becomes `chops corn`, `disk` becomes `disc`, `their car` becomes `the car`. Those are not acoustic confusions of the kind whisper and Parakeet make — they are fluent rewrites, which is exactly what you do not want from the layer whose job is to be literal.

It does hold the meta-speech Parakeet loses (`polish-11`'s quote/unquote, `polish-38`'s spelled letters, though the letters arrive unhyphenated as `S A N D B E R G`), and it is the most faithful engine on disfluency: `polish-01` arrives as `So um I think we should um probably ship it today` with both fillers intact, where whisper, Cohere, and Scribe all thin them.

## The one thing it is good at

Instructed vocabulary. Told the fifteen `wants` terms in the transcription instruction, it reaches **18/18 recall** — the only arm besides the DICTIONARY block to recover every term — and bites 4/8 traps doing it. See [asr-prompting](../asr-prompting/README.md). That is the shape of the thing: it will do whatever you ask, including things you did not want.

## Verdict

Not a candidate. At 2.3 s of engine latency before any cleanup runs, its best e2e cell is 18/27 at 5.9 s — three entries behind Scribe at two and a half times the wait. It is measured so the question stops being asked.
