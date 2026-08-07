# MiniWhisper

MiniWhisper is a macOS menu bar dictation app. It records from your chosen microphone, transcribes speech locally, and pastes the result into the frontmost app.

Hold the dictation shortcut (right Option by default) while you speak, and release it to transcribe. Double-tap it to keep recording without holding; tap once to finish. The shortcut is chosen during setup and rebindable in Settings, where more than one binding can be recorded.

## Install

MiniWhisper requires an Apple silicon Mac running macOS 26 or later.

```sh
brew install thurstonsand/tap/mini-whisper
```

The speech model is downloaded on first run and is not included in the app bundle.

## Permissions

Onboarding asks for two macOS permissions:

- **Microphone** lets it record speech for local transcription.
- **Accessibility** covers the rest: watching for the activation shortcut while another app is active, sending Command-V to the frontmost app, and reading the text around the insertion point.

If automatic paste is unavailable, MiniWhisper leaves the transcript on the clipboard instead.

## Settings

Settings are stored at `~/Library/Application Support/MiniWhisper/settings.json`. The file currently controls the hotkey and sounds.

## Building from source

Building requires Xcode and [mise](https://mise.jdx.dev).

```sh
git clone https://github.com/thurstonsand/mini-whisper.git
cd mini-whisper
mise trust && mise bootstrap
mise run mw   # build and run
mise run test # run the test suite
```

## Attribution

MiniWhisper downloads and uses [NVIDIA Parakeet TDT 0.6B v2](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2) for speech recognition. NVIDIA licenses the model weights under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). The model is downloaded at first run and is not redistributed in the MiniWhisper app bundle.

Transcription is integrated through [FluidAudio](https://github.com/FluidInference/FluidAudio), licensed under the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).

## License

MiniWhisper's source code is available under the [MIT License](LICENSE).
