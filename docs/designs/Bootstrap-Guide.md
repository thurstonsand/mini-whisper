# MiniWhisper Bootstrap Guide

A step-by-step guide to scaffolding a macOS menu bar dictation app using **only Apple-native tooling** plus whisper.cpp.

## Constraints

- **Zero external dev tools** — no SwiftLint, SwiftFormat, Homebrew packages
- **One external runtime dependency** — whisper.cpp (intentional, core to the app)
- **CLI-first workflow** — daily operations via terminal, Xcode GUI only for one-time setup
- **Modular architecture** — local SwiftPM packages for testability and isolation

---

## What We're Using

| Category           | Tool                        | Source                 |
| ------------------ | --------------------------- | ---------------------- |
| Build system       | `xcodebuild`, `swift build` | Xcode                  |
| Testing            | Swift Testing + XCTest      | Xcode 16               |
| Formatting         | `swift format`              | Swift toolchain        |
| Package management | SwiftPM (local packages)    | Swift toolchain        |
| UI framework       | SwiftUI + MenuBarExtra      | macOS 13+              |
| ASR engine         | whisper.cpp XCFramework     | External (intentional) |

---

## Project Structure (Target)

```
mini-whisper/
├── MiniWhisper.xcodeproj/          # Xcode project (app shell)
├── MiniWhisper/                    # App target source
│   ├── App.swift                   # @main entry point
│   ├── MenuBarView.swift           # MenuBarExtra UI
│   ├── Info.plist
│   └── MiniWhisper.entitlements
├── Packages/                       # Local SwiftPM packages
│   ├── AudioCapture/               # AVAudioEngine, ring buffer, VAD
│   ├── ASREngine/                  # Protocol + whisper.cpp wrapper
│   ├── TranscriptCleanup/          # Optional LLM cleanup client
│   └── HotkeyListener/             # Global hotkey handling
├── Frameworks/                     # Embedded frameworks
│   └── whisper.xcframework/
├── Makefile                        # CLI automation
└── docs/
```

---

## Phase 1: One-Time Xcode Setup (GUI Required)

These steps require Xcode's GUI. Do them once, then work from CLI.

### Step 1.1: Create the Xcode Project

1. Open Xcode
2. File → New → Project
3. Select **macOS → App**
4. Configure:
   - Product Name: `MiniWhisper`
   - Team: (your dev team or Personal Team)
   - Organization Identifier: `com.yourname`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Storage: None
   - ✅ Include Tests (select "Swift Testing" as testing system)
5. Save to your `mini-whisper` directory

### Step 1.2: Configure as Menu Bar App

1. Select the project in Navigator
2. Select the `MiniWhisper` target
3. Go to **Info** tab
4. Add key: `Application is agent (UIElement)` = `YES`
   - This hides the app from Dock and Cmd+Tab

### Step 1.3: Add Entitlements

1. Select target → **Signing & Capabilities**
2. Click **+ Capability**
3. Add:

   - **App Sandbox** (required for distribution)
   - Under App Sandbox, enable:
     - ✅ Audio Input (for microphone access)
     - ✅ Outgoing Connections (Client) — if using cleanup API

4. Verify `MiniWhisper.entitlements` file was created with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

### Step 1.4: Add Microphone Usage Description

1. Select target → **Info** tab
2. Add key: `Privacy - Microphone Usage Description`
3. Value: `"MiniWhisper needs microphone access to transcribe your speech."`

### Step 1.5: Create Local Packages

For each package, in Xcode:

1. File → New → Package
2. Select **Library** template
3. Name it (e.g., `AudioCapture`)
4. **Important**: Save inside `Packages/` folder in your project
5. Uncheck "Create Git repository" (already in project repo)

Create these packages:

- `AudioCapture`
- `ASREngine`
- `TranscriptCleanup`
- `HotkeyListener`

### Step 1.6: Link Packages to App Target

1. Select project → `MiniWhisper` target → **General** tab
2. Scroll to "Frameworks, Libraries, and Embedded Content"
3. Click **+**
4. Select each local package's library product and add it

### Step 1.7: Add whisper.cpp XCFramework (Later)

We'll add this after building whisper.cpp. For now, leave a placeholder.

---

## Phase 2: CLI Workflow Setup

After one-time setup, everything below is CLI.

### Step 2.1: Verify Build Works

```bash
cd /path/to/mini-whisper

# List schemes
xcodebuild -list

# Build
xcodebuild -scheme MiniWhisper -destination 'platform=macOS' build

# Run (after successful build)
open ~/Library/Developer/Xcode/DerivedData/MiniWhisper-*/Build/Products/Debug/MiniWhisper.app
```

### Step 2.2: Create Makefile

Create `Makefile` at project root:

```makefile
.PHONY: build run test test-packages format clean help

SCHEME := MiniWhisper
DEST := platform=macOS
DERIVED_DATA := .build/DerivedData
APP_PATH := $(DERIVED_DATA)/Build/Products/Debug/$(SCHEME).app

# === App Targets ===

build:
	xcodebuild -scheme $(SCHEME) \
		-destination '$(DEST)' \
		-derivedDataPath $(DERIVED_DATA) \
		build

run: build
	open $(APP_PATH)

test:
	xcodebuild -scheme $(SCHEME) \
		-destination '$(DEST)' \
		-derivedDataPath $(DERIVED_DATA) \
		test

# === Package Targets (fast, no Xcode overhead) ===

build-packages:
	@for pkg in Packages/*/; do \
		echo "Building $$pkg..."; \
		swift build --package-path "$$pkg" || exit 1; \
	done

test-packages:
	@for pkg in Packages/*/; do \
		echo "Testing $$pkg..."; \
		swift test --package-path "$$pkg" || exit 1; \
	done

# === Code Quality ===

format:
	swift format --recursive --in-place Sources/ Packages/

format-check:
	swift format --recursive Sources/ Packages/ 2>&1 | grep -q "would be reformatted" && exit 1 || exit 0

# === Maintenance ===

clean:
	rm -rf $(DERIVED_DATA)
	rm -rf .build
	@for pkg in Packages/*/; do \
		swift package --package-path "$$pkg" clean; \
	done

# === Help ===

help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "App targets:"
	@echo "  build          Build the app"
	@echo "  run            Build and run the app"
	@echo "  test           Run app tests"
	@echo ""
	@echo "Package targets:"
	@echo "  build-packages Build all local packages"
	@echo "  test-packages  Test all local packages"
	@echo ""
	@echo "Quality:"
	@echo "  format         Format all Swift code"
	@echo "  format-check   Check formatting (CI)"
	@echo ""
	@echo "Maintenance:"
	@echo "  clean          Remove build artifacts"
```

### Step 2.3: Create .swift-format Configuration

Create `.swift-format` at project root:

```json
{
  "version": 1,
  "indentation": {
    "spaces": 4
  },
  "tabWidth": 4,
  "maximumBlankLines": 1,
  "respectsExistingLineBreaks": true,
  "lineBreakBeforeControlFlowKeywords": false,
  "lineBreakBeforeEachArgument": false,
  "lineBreakBeforeEachGenericRequirement": false,
  "prioritizeKeepingFunctionOutputTogether": true,
  "indentConditionalCompilationBlocks": true,
  "lineLength": 120,
  "rules": {
    "AllPublicDeclarationsHaveDocumentation": false,
    "AlwaysUseLowerCamelCase": true,
    "AmbiguousTrailingClosureOverload": true,
    "NoAccessLevelOnExtensionDeclaration": true,
    "OrderedImports": true,
    "UseLetInEveryBoundCaseVariable": true,
    "UseSynthesizedInitializer": true
  }
}
```

---

## Phase 3: Minimal Hello World Menu Bar App

### Step 3.1: Replace App.swift

Replace `MiniWhisper/App.swift`:

```swift
import SwiftUI

@main
struct MiniWhisperApp: App {
    var body: some Scene {
        MenuBarExtra("MiniWhisper", systemImage: "waveform") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }
}
```

### Step 3.2: Create MenuBarView.swift

Create `MiniWhisper/MenuBarView.swift`:

```swift
import SwiftUI

struct MenuBarView: View {
    @State private var isListening = false

    var body: some View {
        VStack(spacing: 12) {
            Text(isListening ? "Listening..." : "Ready")
                .font(.headline)

            Button(isListening ? "Stop" : "Start") {
                isListening.toggle()
            }
            .keyboardShortcut(.return, modifiers: [])

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding()
        .frame(width: 200)
    }
}

#Preview {
    MenuBarView()
}
```

### Step 3.3: Verify It Works

```bash
make build
make run
```

You should see a waveform icon in the menu bar. Click it to see the popup.

---

## Phase 4: Set Up Local Packages

### Step 4.1: AudioCapture Package

Edit `Packages/AudioCapture/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AudioCapture",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AudioCapture", targets: ["AudioCapture"]),
    ],
    targets: [
        .target(name: "AudioCapture"),
        .testTarget(
            name: "AudioCaptureTests",
            dependencies: ["AudioCapture"]
        ),
    ]
)
```

Create `Packages/AudioCapture/Sources/AudioCapture/AudioCaptureService.swift`:

```swift
import AVFoundation
import Foundation

/// Protocol for audio capture, enabling test mocking
public protocol AudioCaptureService: Sendable {
    func requestPermission() async -> Bool
    func startCapture() async throws
    func stopCapture() async
}

/// Production implementation using AVAudioEngine
public actor AudioEngine: AudioCaptureService {
    private let engine = AVAudioEngine()
    private var isRunning = false

    public init() {}

    public func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    public func startCapture() async throws {
        guard !isRunning else { return }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, time in
            // TODO: Forward audio buffers to processing pipeline
        }

        try engine.start()
        isRunning = true
    }

    public func stopCapture() async {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }
}
```

Create a test at `Packages/AudioCapture/Tests/AudioCaptureTests/AudioCaptureTests.swift`:

```swift
import Testing
@testable import AudioCapture

@Test("AudioEngine initializes without error")
func audioEngineInitializes() async {
    let engine = AudioEngine()
    // Just verify it doesn't crash on init
    #expect(engine != nil)
}
```

### Step 4.2: Verify Package Builds/Tests

```bash
# Build just this package
swift build --package-path Packages/AudioCapture

# Test just this package
swift test --package-path Packages/AudioCapture

# Or all packages
make test-packages
```

---

## Phase 5: Add whisper.cpp (When Ready)

### Step 5.1: Clone and Build XCFramework

```bash
# Clone whisper.cpp
git clone https://github.com/ggerganov/whisper.cpp.git /tmp/whisper.cpp
cd /tmp/whisper.cpp

# Build XCFramework for macOS
./build-xcframework.sh

# Copy to project
cp -r build-apple/whisper.xcframework /path/to/mini-whisper/Frameworks/
```

### Step 5.2: Add to Xcode Project (GUI)

1. In Xcode, drag `Frameworks/whisper.xcframework` into Navigator
2. Select target → **General** → "Frameworks, Libraries, and Embedded Content"
3. Ensure whisper.xcframework shows with "Embed & Sign"

### Step 5.3: Download a Model

```bash
mkdir -p ~/Library/Application\ Support/MiniWhisper/Models
cd ~/Library/Application\ Support/MiniWhisper/Models

# Download base.en quantized model (~57MB)
curl -L -o ggml-base.en-q5_1.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en-q5_1.bin
```

---

## Phase 6: Daily Workflow

```bash
# Start of day
cd /path/to/mini-whisper

# Quick iteration on packages (fast)
make test-packages

# Full app build + test
make test

# Format before commit
make format

# Run the app
make run
```

---

## Appendix A: Enabling Strict Compiler Checks

For lint-like behavior without external tools, enable strict Swift settings.

In Xcode (one-time), or add to `xcodebuild` command:

```bash
# Strict concurrency (catches data races)
xcodebuild ... OTHER_SWIFT_FLAGS="-strict-concurrency=complete"

# Warnings as errors
xcodebuild ... GCC_TREAT_WARNINGS_AS_ERRORS=YES SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
```

Or add to Makefile:

```makefile
STRICT_FLAGS := OTHER_SWIFT_FLAGS="-strict-concurrency=complete" \
                GCC_TREAT_WARNINGS_AS_ERRORS=YES \
                SWIFT_TREAT_WARNINGS_AS_ERRORS=YES

build-strict:
	xcodebuild -scheme $(SCHEME) -destination '$(DEST)' $(STRICT_FLAGS) build
```

---

## Appendix B: Global Hotkeys (Apple-Native)

For global hotkeys without external deps, use Carbon API (still supported):

```swift
import Carbon

func registerHotkey() {
    var hotKeyRef: EventHotKeyRef?
    var hotKeyID = EventHotKeyID()
    hotKeyID.signature = OSType("htky".fourCharCode)
    hotKeyID.id = 1

    // Cmd+Shift+Space
    let keyCode: UInt32 = 49  // Space
    let modifiers: UInt32 = UInt32(cmdKey | shiftKey)

    RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                        GetApplicationEventTarget(), 0, &hotKeyRef)
}
```

This is verbose but avoids external dependencies. Consider wrapping in your `HotkeyListener` package.

---

## Appendix C: CI/CD Script

For automated builds (GitHub Actions, etc.):

```yaml
# .github/workflows/build.yml
name: Build

on: [push, pull_request]

jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_16.app

      - name: Build packages
        run: make build-packages

      - name: Test packages
        run: make test-packages

      - name: Format check
        run: make format-check

      - name: Build app
        run: make build

      - name: Test app
        run: make test
```

---

## Summary

| Phase | What                                         | CLI or GUI                  |
| ----- | -------------------------------------------- | --------------------------- |
| 1     | Create Xcode project, entitlements, packages | GUI (one-time)              |
| 2     | Set up Makefile, .swift-format               | CLI                         |
| 3     | Hello world menu bar app                     | CLI                         |
| 4     | Flesh out packages                           | CLI                         |
| 5     | Add whisper.cpp                              | GUI (embed framework) + CLI |
| 6+    | Daily development                            | CLI                         |

You now have a fully Apple-native toolchain with CLI-first workflow. The only external dependency is whisper.cpp, which is core to your app's purpose.
