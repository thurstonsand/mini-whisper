# Context

- MiniWhisper: this project — a macOS menu bar dictation app that transcribes speech locally and delivers the text into the frontmost app.
- Activate: start the actual process that leads to dictation; triggered by the press of a configured keybind
- Record: the act of recording audio
- Transcribe: STT
- Delivery: placing the transcript where the user was typing.
- Dictation: one full pass through the vertical — activate, record, transcribe, deliver.
- Hold: hold the keybind to record, release to transcribe.
- Latch: double-tap the keybind to keep recording without holding; a single tap ends it and transcribes. A lone tap is a near-no-op (records for a split second, yields nothing).
- Silence rejection: preprocessing that keeps silence and near-silence from reaching the engine, so empty recordings never produce hallucinated text.
- The gate: the silence-rejection implementation — one whole-utterance Silero VAD classification at release; accepted audio passes to the engine unchanged.
- Engine: an implementation of the transcription protocol in `ASREngine` (pinned FluidAudio + Parakeet TDT v2 for MVP; whisper.cpp Medium.en is the recorded fallback, not shipped).
- The pill: the bottom-center HUD panel that owns all dictation-time state (recording, latch, transcribing, transient notices). Success is its disappearance.
- Degraded: a failure state represented in the menu bar — missing Input Monitoring, blocked microphone, a dead event tap, or an uninstalled/failed model.
- Onboarding: the app's only modal flow — welcome, sequential permissions, model download/compile/prewarm, and one real try-it dictation; the welcome button records bandwidth consent and starts a durable background download that resumes across relaunches.
- Settings file: `~/Library/Application Support/MiniWhisper/settings.json`, the human-editable settings surface until the settings UI stake lands.
- Field context: the text around the insertion point of the focused field.
- Cleanup pass: the optional post-transcription LLM pass, talking to a configurable OpenAI-compatible endpoint.
- The allowlist: A list of permitted software/libraries.
