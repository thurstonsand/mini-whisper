# Paid dictation-app dictionary mechanisms

**Scope.** This examines public evidence available 2026-08-10. These apps are closed source, so a product page saying “dictionary” is evidence of a user-visible claim, not of its implementation. “Direct” below means the vendor or its infrastructure provider states the fact; “inference” is explicitly marked. It does not treat a correction rule as recognition bias.

## Short answer

| App          | ASR stack                                                                                                                                      | Dictionary / vocabulary mechanism                                                                                                                                                                                                                                                                           | Evidence strength                                                                          |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| Wispr Flow   | Cloud ASR, model undisclosed; cloud Llama transcript-cleanup stage on Baseten/AWS                                                              | **Direct:** calls vocabulary entries “word boosting” during transcription; separately applies explicit misspelling replacements after dictation. **Unknown:** whether boosting is an ASR-provider keyword API, a custom decoder, or a dictionary-aware LLM/ASR pipeline.                                    | High for feature split and cloud/Llama stages; low for exact boost implementation          |
| Aqua Voice   | Cloud-hosted proprietary Avalon (remote API); separate “underlying Large Language Models”                                                      | Claims a custom dictionary improves Avalon accuracy and has separate Custom Instructions and Replacements. No public parameter, decoder description, or statement that the dictionary is supplied to an LLM was found.                                                                                      | High for Avalon/cloud and feature claim; low for mechanism                                 |
| Monologue    | Selectable cloud transcription (provider undisclosed); local Apple-silicon FluidAudio Parakeet TDT v3 plus `parakeet-ctc-110m` assets          | Dictionary plus a separate word-replacement feature. **Likely, not confirmed:** the local path uses FluidAudio’s CTC vocabulary-rescoring sidecar; that exact sidecar asset is downloaded alongside TDT. Remote behavior is undisclosed.                                                                    | High for local stack/assets and replacement feature; medium for CTC-rescoring inference    |
| Superwhisper | Model-selectable: local Whisper and Parakeet; cloud providers/models including Deepgram, OpenAI/Groq, ElevenLabs; other models vary by release | **Direct:** sends vocabulary recognition hints with audio; deterministic case-insensitive replacements run post-transcription. The per-model mechanism is not published. Changelogs show vocabulary support differs by model, including Parakeet support and a later disablement for multilingual Parakeet. | High for feature split and multi-stack status; medium for any individual model’s mechanism |
| MacWhisper   | Local Whisper, Parakeet, and other models; optional external AI services                                                                       | Public site documents _custom prompts to enhance transcriptions_, not a dictionary/vocabulary feature or mechanism. Do not count it as paid-app vocabulary precedent.                                                                                                                                       | High for stack/prompt claim; no dictionary evidence                                        |

## Primary apps

### Wispr Flow

**What it claims — direct evidence (high confidence).** Its [Dictionary help article](https://docs.wisprflow.ai/articles/4052411709-teach-flow-your-words-with-the-dictionary) expressly divides entries into **Vocabulary words**, which provide “Word boosting” and “improve recognition accuracy … during transcription,” and **replacement rules**, which “automatically swap one spelling for another.” It says replacements and snippets apply as soon as dictation finishes. A CSV import similarly distinguishes one-column vocabulary terms from two-column misspelling/correction pairs. This is the cleanest public paid-app statement that these are two different mechanisms.

**Stack — direct evidence (high confidence).** Flow says [transcription always happens in the cloud](https://wisprflow.ai/privacy). A [Baseten customer case study](https://www.baseten.co/resources/customers/wispr-flow/) says its end-to-end pipeline has speech-recognition models followed by a fine-tuned Llama transcript-enhancement step, served by Baseten on AWS. The case study identifies Llama only for cleanup/context/preference tasks; it does **not** name the ASR model or provider.

**Actual dictionary mechanism — bounded inference (low confidence on the exact implementation).** “During transcription” and the deliberate contrast with after-dictation replacements are good evidence that vocabulary is intended to affect recognition rather than be a blind find/replace. They do not establish _how_. Public sources do not say that Flow calls Deepgram keywords/keyterms, AssemblyAI word boost, a Whisper prompt, a proprietary decoder bias, or Llama with a dictionary instruction. The documented Llama cleanup stage could also see vocabulary, but there is no evidence it is the source of the claimed word boost. The honest conclusion is **cloud recognition-stage vocabulary bias of unspecified kind, plus deterministic text replacements**.

### Aqua Voice

**What it claims — direct evidence (high confidence).** Aqua’s [product page](https://aquavoice.com/) says its Custom Dictionary teaches names, brands, and technical terms and “accuracy improve[s] instantly”; the paid plan lists 800 dictionary values. Its [changelog](https://aquavoice.com/changelog) separately records “Bulk-add terms to Custom Dictionary,” dictionary reliability improvements “for users of the Avalon model,” and separate Custom Instructions and Replacements features.

**Stack — direct evidence (high confidence).** [Avalon is Aqua’s proprietary speech-recognition model](https://aquavoice.com/blog/introducing-avalon), trained for human–computer interaction and technical/coding language. Aqua exposes the same model as an [OpenAI-SDK-compatible remote transcription API](https://aquavoice.com/avalon-api), with `base_url="https://api.aquavoice.com/v1"`; its privacy policy describes server-side transcription processing. That makes Aqua Voice a cloud ASR product, not a local-model precedent. The changelog’s reference to both Avalon and “underlying Large Language Models” supports a multi-stage ASR-plus-text-processing pipeline, but does not name those LLMs or their inputs.

**Actual dictionary mechanism — unknown (low confidence).** The public material never specifies an Avalon request field, boosting algorithm, prompt, or post-pass. It is reasonable to infer that the dictionary is passed into Aqua’s hosted recognition pipeline because it is described as improving Avalon recognition and has an Avalon-specific reliability fix, but it would be speculation to call it an API keyword boost, decoder logit bias, or LLM instruction. **Do not use Aqua as evidence that an LLM post-formatter implements dictionaries.** Its UI separates dictionary, instructions, and replacements, but their internal ordering is unpublished.

### Monologue

**What it claims — direct evidence (high confidence).** Monologue’s [site](https://www.monologue.to/) says its dictionary stores names, acronyms, and company vernacular and uses them everywhere. Its [v1.0.47 changelog](https://feedback.monologue.to/changelog) separately introduced **Word Replacements** mapping misheard words/phrases to preferred text. So, as with Flow, the paid product distinguishes a dictionary from explicit corrections. Its site also separates custom instructions/modes and network-backed context-aware formatting from local transcription.

**Stack — direct evidence (high confidence).** Monologue permits Local or Remote transcription. Its [local-model transfer guide](https://help.monologue.to/en/articles/14270611-how-do-i-transfer-the-local-model-to-another-mac) names the downloaded local directories exactly:

- `FluidAudio/Models/parakeet-tdt-0.6b-v3-coreml`
- `FluidAudio/Models/parakeet-ctc-110m-coreml`

The [processing-mode guide](https://help.monologue.to/en/articles/14178204-how-do-i-switch-between-local-and-cloud-processing) says Remote sends audio to Monologue’s servers, then deletes it; it does not disclose that provider or model. Even in Local mode, polished/context-aware formatting remains network-backed and falls back to raw transcription if unavailable.

**Actual dictionary mechanism — CTC-sidecar inference (medium confidence).** The asset pair is not merely “Parakeet exists”: `parakeet-ctc-110m-coreml` is the separately distributed CTC vocabulary-boosting model documented by [FluidAudio v0.15.5](https://github.com/FluidInference/FluidAudio/blob/v0.15.5/Documentation/ASR/CustomVocabulary.md). That is strong circumstantial evidence that Monologue’s local dictionary can use the same CTC-WS-style acoustic spotting/rescoring route as MiniWhisper could. Monologue has not published its call site, configuration, or whether it always enables the sidecar, so this must remain an inference rather than a confirmed implementation claim. Its remote-dictionary path is completely unknown.

This is the most relevant paid precedent: it appears to ship the same local TDT plus CTC-sidecar assets, while retaining separate word replacements and cloud text formatting.

## Secondary evidence

### Superwhisper

Superwhisper’s [Vocabulary documentation](https://superwhisper.com/docs/get-started/interface-vocabulary) is unusually direct: vocabulary terms are “custom recognition hints” **sent alongside audio** to the selected transcription model; replacements run after transcription, programmatically, case-insensitively, and preserve the author’s replacement casing. That establishes neither a shared algorithm nor a single ASR stack. The [product documentation](https://superwhisper.com/docs) exposes cloud and local models, while its [changelog](https://superwhisper.com/changelog) records vocabulary support across WhisperKit/Deepgram, Parakeet vocabulary support, a disablement for multilingual Parakeet, and later Whisper-offline forced-alignment/vocabulary improvements. Model-specific behavior is exactly what one would expect when an app maps one UI list onto several incompatible APIs and decoders.

This is useful corroboration, not a mechanism disclosure. “Sent alongside audio” could map to a Whisper prompt, a cloud vendor’s keyword parameter, or Superwhisper-owned processing depending on the selected model. Its explicit deterministic replacement stage is the only part whose mechanism is public.

### MacWhisper and Whispering

MacWhisper’s [site](https://www.macwhisper.com/) states that it uses local Whisper, Parakeet, and other models and offers “Custom prompts” to _enhance_ transcriptions, along with optional external AI services. No official dictionary/custom-vocabulary claim or implementation was located, so no conclusion should be drawn from it. No comparably reliable, easy primary source was located for Whispering; it is omitted rather than filled with review-site conjecture.

## What this changes for MiniWhisper

### Prompting and biasing are model/runtime/API-specific

**No: prompt-based pre-transcription conditioning is not universal, and it is not literally exclusive to Whisper.** A Whisper-style initial prompt is a facility of an autoregressive text decoder and the runtime/API that exposes it. Other encoder–decoder models can have analogous decoder context. Separately, an ASR vendor can expose keyword/keyterm/word-boost parameters even when its model is not Whisper. Neither is a hard vocabulary guarantee.

A transducer is not thereby unable to be biased. NeMo documents GPU-PB shallow-fusion token boosting for CTC, RNN-T/TDT, and AED decoding, but it is a specific CUDA/NGPU-LM decoder capability. It also documents CTC-WS for a Transducer only when there is a hybrid Transducer–CTC model with a CTC head. [NeMo word boosting](https://docs.nvidia.com/nemo-framework/user-guide/latest/nemotoolkit/asr/asr_customization/word_boosting.html)

So the operative rule is **the model plus the decoder/runtime/API determines what conditioning exists**. Whisper prompts, cloud keyword parameters, and NeMo GPU-PB are different facilities. A UI called “Dictionary” establishes none of them by itself.

### The precise local conclusion for Parakeet TDT v2/Core ML

For **MiniWhisper’s shipped FluidAudio v0.15.5 Parakeet TDT v2/Core ML path**, the prior research remains correct: there is no initial-prompt argument or exposed TDT decoder-logit-bias API. FluidAudio’s usable recognition-time-ish route is its optional CTC 110M sidecar: run the primary TDT decode, score candidate terms against CTC acoustic log probabilities, and replace only when the candidate wins the acoustic comparison. [FluidAudio custom-vocabulary documentation](https://github.com/FluidInference/FluidAudio/blob/v0.15.5/Documentation/ASR/CustomVocabulary.md#L20-L36) [MiniWhisper baseline](parakeet-vocabulary-hinting.md)

Call that **the only exposed, practical local acoustic vocabulary mechanism in this selected runtime**, not the only mechanism possible for every transducer. A different local runtime could implement NeMo-style decode-time boosting, use a hybrid TDT/CTC model, or be retrained; those capabilities were not converted into MiniWhisper’s Core ML bundle. Plain deterministic correction also remains available locally, but is text transformation, not recognition conditioning.

The paid-app evidence does not weaken the proposed CTC-sidecar experiment. It reinforces the product split already selected for MiniWhisper: vocabulary terms need a recognition path, while correction pairs need deterministic post-transcription replacement. It also reinforces the disclosure/default-off caution: even a paid app that claims “word boosting” rarely publishes an accuracy or false-replacement guarantee. Monologue is the closest observed local precedent and appears to carry the same FluidAudio sidecar assets, but its closed implementation cannot validate MiniWhisper’s threshold or latency trade-off.
