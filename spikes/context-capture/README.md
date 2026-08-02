# Context-capture spike

Disposable macOS Accessibility API probe for ticket 20. It is not an Xcode target and must not ship with MiniWhisper.

```sh
swiftc -warnings-as-errors -framework AppKit -framework ApplicationServices -framework Foundation \
  spikes/context-capture/ContextCaptureProbe.swift -o .build/context-capture-probe
.build/context-capture-probe 256 --delay=5
```

The delay gives the operator time to focus the desired editable element after submitting the command. `--activate-chromium` tries `AXManualAccessibility` first and then the older `AXEnhancedUserInterface`; `--activation-settle=<seconds>` controls its wait. `--wake-chromium` walks the frontmost AX tree for diagnosis, and `--messaging-timeout=<seconds>` applies a timeout to the app and resolved field.

The probe prints role, exposed attributes, value, selected text/range, character count, a `AXStringForRange` read around the selection, and the insertion-point line. It measures each AX request independently and falls back from system-wide focus to the frontmost application PID.
