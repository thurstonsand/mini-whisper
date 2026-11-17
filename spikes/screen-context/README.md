# Screen-context spike

Disposable probes for giving the cleanup pass what is on screen around the field, not only the field. None of this is an Xcode target or ships with MiniWhisper.

```sh
# Both are top-level-code files, so compile each as main.swift.
cp spikes/screen-context/AXWindowProbe.swift .build/main.swift
swiftc -O -framework AppKit -framework ApplicationServices .build/main.swift -o .build/AXWindowProbe
cp spikes/screen-context/ScreenOCRProbe.swift .build/main.swift
swiftc -O -framework AppKit -framework ApplicationServices -framework ScreenCaptureKit \
  -framework Vision -framework CoreML .build/main.swift -o .build/ScreenOCRProbe

.build/AXWindowProbe --nodes=2000 --budget-ms=250     # walk the frontmost focused window
.build/ScreenOCRProbe --mode=rect --save=/tmp/w.png   # rect | window | display
```

`AXWindowProbe` walks the frontmost app's focused window breadth-first under a node cap and a time budget, prints every text-bearing leaf with its role and depth, and marks the focused element with `*`. It uses `AXChildren`, not `AXVisibleChildren`, which a Safari window does not answer at all. Run it twice against a freshly opened Safari: the first walk finds only the window's chrome, because Safari builds a page's tree on the first query it receives.

`ScreenOCRProbe` captures the focused window (located through AX, since ScreenCaptureKit has no "frontmost window" selector) and runs Vision text recognition, timing each stage. `--mode=rect` uses the macOS 15.2 `captureImage(in:)` route that acquires only the rectangle; `--mode=window` enumerates shareable content and bridges AX to an `SCWindow` by PID and frame. `--cpu` forces the legacy `VNRecognizeTextRequest` onto the CPU, which a virtualized Mac needs: it has no Neural Engine, and `.accurate` fails to compile its model on the paravirtual GPU (`e5rt_e5_compiler_compile`), so only `.fast` can be measured there.

`scene/` holds the two staged targets: `agent.sh` prints a coding-agent transcript for a tmux pane, and `chat.html` is a chat page with a focused composer.

`eval/screen_context_eval.py` replays dictations through the app's own built-in prompt, lifted from `CleanupPrompt.swift`, once per context arm (none, field, structural text, OCR text, screenshot at 2x and 1x, screenshot plus field), and scores whether the identifiers only the screen can supply come back. The scenes' text and OCR output are inlined in the script; the screenshots are read from the directory given as its first argument.

`collect/` gathers the stage 4 scenes in `43-dictation-corpus/stage4-screen.jsonl` from a real screen. `collect.py --id ID [--live]` runs `screen-collect` against the frontmost focused window and keeps every source side by side: the field, the Accessibility walk as composed text and as framed lines, the tmux pane, Vision `.accurate` text and lines, and the Retina and 1x screenshots. It also renders the line with `say`, and with `--live` plays it through BlackHole into MiniWhisper Dev and keeps the History entry the app wrote. `recompose CAPTURE_DIR...` rewrites each capture's `ax.txt` and `ocr.txt` from its lines through the current `VisibleText.compose`, so a change to composition needs no recapture. `to_history.py --out DIR` turns the scenes into one History directory per source (`ax`, `tmux`, `ocr`, and `app`, which picks among them as the app does: tmux, else Accessibility unless `meta.json`'s `axUnplaced` says the walk met text it could not place, else OCR), each with the `cases.jsonl` `replay_history.py` scores against. With `--transcripts`, an `asr-replay` JSONL of human recordings (`record.py stage4-screen.jsonl --label thurston`, replayed through `asr-replay --stage stage4-screen.jsonl --recordings recordings/stage4-screen-thurston`) replaces the `say` transcripts.

`eval/replay_history.py` replays a History directory's entries that carry screen context under each context arm (field, text, image) crossed with each thinking arm: `default`, what the app sends today, and `off`, the provider's own switch, chosen by the endpoint's host. For Anthropic that is `thinking: {"type": "disabled"}`, the only reasoning control its OpenAI-compatible endpoint honours for Claude 5 models; it ignores `reasoning_effort` and `effort`, turns `enabled` with `budget_tokens` into adaptive thinking, and refuses `adaptive`. For OpenAI it is `reasoning_effort: "none"`; GPT-6 models refuse `minimal`. It reports accuracy, regressions against field+default, completion tokens, p50 and p95 latency, and the runs past the cleanup timeout. Any directory shaped like History works, so hand-written scenes replay the same way captured ones do.
