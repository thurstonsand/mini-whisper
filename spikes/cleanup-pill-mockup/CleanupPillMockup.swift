// Disposable mock-up for ticket 41: the pill during a blocking cleanup pass.
// Standalone — imports no MiniWhisper code; the pill chrome below is copied from
// PillView.swift so variants are judged on the real capsule, materials, and type.
//
//   swiftc -framework AppKit -framework SwiftUI \
//     spikes/cleanup-pill-mockup/CleanupPillMockup.swift -o .build/cleanup-pill-mockup
//   .build/cleanup-pill-mockup            # gallery: all variants at once
//   .build/cleanup-pill-mockup live      # plays the full sequence with real timings
//   Trailing `light` or `dark` forces that appearance.

import AppKit
import SwiftUI

// MARK: - Pill chrome (copied from PillView.swift)

struct PillChrome<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    content
      .padding(.horizontal, 15)
      .frame(height: 46)
      .background(.regularMaterial, in: Capsule())
      .overlay {
        Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
      }
      .shadow(color: .black.opacity(0.24), radius: 12, y: 5)
      .frame(width: 420, height: 76)
  }
}

struct PulsingDot: View {
  var color = Color(red: 0.20, green: 0.53, blue: 1)
  var glow = Color.blue

  @State private var isPulsing = false

  var body: some View {
    Circle()
      .fill(color)
      .frame(width: 9, height: 9)
      .shadow(color: glow.opacity(0.45), radius: 3)
      .scaleEffect(isPulsing ? 0.82 : 1)
      .opacity(isPulsing ? 0.48 : 1)
      .task {
        withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
          isPulsing = true
        }
      }
  }
}

func pillText(_ text: String, subdued: Bool = false) -> some View {
  Text(text)
    .font(.system(size: 13, weight: .medium))
    .foregroundStyle(subdued ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
}

// MARK: - Keycaps (miniature of HotkeyKeycaps.swift, scale 0.85)

struct MiniKeycaps: View {
  let components: [String]
  var scale: CGFloat = 0.85

  var body: some View {
    HStack(spacing: 3 * scale) {
      ForEach(Array(components.enumerated()), id: \.offset) { _, component in
        Text(component)
          .font(.system(size: 12 * scale))
          .padding(.horizontal, 7 * scale)
          .padding(.vertical, 3 * scale)
          .background {
            RoundedRectangle(cornerRadius: 5 * scale).fill(.quaternary)
          }
      }
    }
    .padding(3 * scale)
    .background {
      RoundedRectangle(cornerRadius: 7 * scale).fill(.quinary)
    }
  }
}

// MARK: - Working-state variants (cleanup in flight, before the skip reveal)

// W1: cleanup is invisible — "Transcribing…" carries the whole tail. Today's presentation.
struct WorkingW1: View {
  var body: some View {
    HStack(spacing: 9) {
      PulsingDot()
      pillText("Transcribing…")
    }
  }
}

// W2: honest phase, same blue dot.
struct WorkingW2: View {
  var body: some View {
    HStack(spacing: 9) {
      PulsingDot()
      pillText("Cleaning up…")
    }
  }
}

// W3: honest phase, its own color — purple marks the network leg.
struct WorkingW3: View {
  var body: some View {
    HStack(spacing: 9) {
      PulsingDot(color: Color(red: 0.62, green: 0.40, blue: 0.95), glow: .purple)
      pillText("Cleaning up…")
    }
  }
}

// W4: wording alternative.
struct WorkingW4: View {
  var body: some View {
    HStack(spacing: 9) {
      PulsingDot(color: Color(red: 0.62, green: 0.40, blue: 0.95), glow: .purple)
      pillText("Polishing…")
    }
  }
}

// MARK: - Skip-affordance variants (≥ 3 s of cleanup)

// S1: notice-style text swap, em-dash pattern from "Copied — ⌘V to paste".
struct SkipS1: View {
  var body: some View {
    HStack(spacing: 9) {
      PulsingDot(color: Color(red: 0.62, green: 0.40, blue: 0.95), glow: .purple)
      pillText("Cleaning up… — ⌥ to paste as heard")
    }
  }
}

// S2: structural keycap chip trailing the phase label.
struct SkipS2: View {
  var body: some View {
    HStack(spacing: 9) {
      PulsingDot(color: Color(red: 0.62, green: 0.40, blue: 0.95), glow: .purple)
      pillText("Cleaning up…")
      Spacer().frame(width: 2)
      MiniKeycaps(components: ["⌥ Opt →"])
      pillText("to skip", subdued: true)
    }
  }
}

// S3: the hint replaces the phase entirely.
struct SkipS3: View {
  var body: some View {
    HStack(spacing: 9) {
      PulsingDot(color: Color(red: 0.62, green: 0.40, blue: 0.95), glow: .purple)
      pillText("⌥ Opt → to paste as heard", subdued: true)
    }
  }
}

// S4: phase left, subdued hint right — two texts sharing the slot.
struct SkipS4: View {
  var body: some View {
    HStack(spacing: 9) {
      PulsingDot(color: Color(red: 0.62, green: 0.40, blue: 0.95), glow: .purple)
      pillText("Cleaning up…")
      pillText("⌥ skip", subdued: true)
    }
  }
}

// Chosen composition (decided in the ticket-41 review): the skip reveal keeps the
// Polishing… phase and adds the keycap chip.
struct SkipChosen: View {
  var body: some View {
    HStack(spacing: 9) {
      PulsingDot(color: Color(red: 0.62, green: 0.40, blue: 0.95), glow: .purple)
      pillText("Polishing…")
      Spacer().frame(width: 2)
      MiniKeycaps(components: ["⌥ Opt →"])
      pillText("to skip", subdued: true)
    }
  }
}

// MARK: - Failure-notice variants (delivered raw; transient, then gone)

struct FailureF1: View {
  var body: some View { pillText("Cleanup unavailable — pasted as heard") }
}

struct FailureF2: View {
  var body: some View { pillText("Pasted as heard — cleanup unavailable") }
}

struct FailureF3: View {
  var body: some View { pillText("Cleanup unavailable — pasted as heard", subdued: true) }
}

// MARK: - Gallery

struct LabeledPill<Content: View>: View {
  let code: String
  let caption: String
  @ViewBuilder var content: Content

  var body: some View {
    VStack(spacing: 0) {
      PillChrome { content }
      HStack(spacing: 6) {
        Text(code).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        Text(caption).font(.caption).foregroundStyle(.tertiary)
      }
    }
  }
}

struct GalleryView: View {
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        Text("Working state — cleanup in flight, first 3 s")
          .font(.headline).padding(.top, 12)
        HStack(spacing: 0) {
          LabeledPill(code: "W1", caption: "cleanup invisible (today's Transcribing…)") { WorkingW1() }
          LabeledPill(code: "W2", caption: "honest phase, blue dot") { WorkingW2() }
        }
        HStack(spacing: 0) {
          LabeledPill(code: "W3", caption: "honest phase, purple dot") { WorkingW3() }
          LabeledPill(code: "W4", caption: "wording: Polishing…") { WorkingW4() }
        }

        Text("Skip affordance — revealed at 3 s").font(.headline).padding(.top, 16)
        HStack(spacing: 0) {
          LabeledPill(code: "S1", caption: "notice-style text swap") { SkipS1() }
          LabeledPill(code: "S2", caption: "keycap chip + subdued verb") { SkipS2() }
        }
        HStack(spacing: 0) {
          LabeledPill(code: "S3", caption: "hint replaces phase") { SkipS3() }
          LabeledPill(code: "S4", caption: "phase + subdued hint") { SkipS4() }
        }

        Text("Failure notice — raw delivered, transient").font(.headline).padding(.top, 16)
        HStack(spacing: 0) {
          LabeledPill(code: "F1", caption: "cause first") { FailureF1() }
          LabeledPill(code: "F2", caption: "result first") { FailureF2() }
        }
        HStack(spacing: 0) {
          LabeledPill(code: "F3", caption: "cause first, subdued") { FailureF3() }
          Spacer().frame(width: 420)
        }
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 24)
    }
    .frame(minWidth: 920, minHeight: 720)
  }
}

// MARK: - Live sequence

struct LiveView: View {
  enum Phase: String {
    case transcribing = "0.0 s — transcribing"
    case cleaning = "1.2 s — cleanup request in flight (Polishing…)"
    case skipHint = "3.0 s — skip affordance reveals"
    case failure = "10.0 s — timeout: raw delivered, notice"
    case gone = "done — pill gone"
  }

  @State private var phase = Phase.transcribing

  var body: some View {
    VStack(spacing: 12) {
      ZStack {
        switch phase {
        case .transcribing:
          PillChrome { WorkingW1() }
        case .cleaning:
          PillChrome { WorkingW4() }
        case .skipHint:
          PillChrome { SkipChosen() }
        case .failure:
          PillChrome { FailureF3() }
        case .gone:
          Color.clear.frame(width: 420, height: 76)
        }
      }
      .animation(.easeOut(duration: 0.16), value: phase)
      Text(phase.rawValue).font(.caption).foregroundStyle(.secondary)
      Button("Replay") { play() }
    }
    .padding(32)
    .frame(minWidth: 560, minHeight: 240)
    .task { play() }
  }

  private func play() {
    phase = .transcribing
    Task {
      try? await Task.sleep(for: .milliseconds(1200))
      phase = .cleaning
      try? await Task.sleep(for: .milliseconds(1800))
      phase = .skipHint
      try? await Task.sleep(for: .milliseconds(3000))
      phase = .failure
      try? await Task.sleep(for: .milliseconds(3000))
      phase = .gone
    }
  }
}

// MARK: - App shell

final class AppDelegate: NSObject, NSApplicationDelegate {
  var window: NSWindow!

  func applicationDidFinishLaunching(_: Notification) {
    let arguments = CommandLine.arguments.dropFirst().map { $0.lowercased() }
    if arguments.contains("light") {
      NSApp.appearance = NSAppearance(named: .aqua)
    } else if arguments.contains("dark") {
      NSApp.appearance = NSAppearance(named: .darkAqua)
    }
    let live = arguments.contains("live")

    let root: NSView =
      live
      ? NSHostingView(rootView: LiveView())
      : NSHostingView(rootView: GalleryView())

    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: live ? 560 : 960, height: live ? 260 : 760),
      styleMask: [.titled, .closable, .resizable, .miniaturizable],
      backing: .buffered, defer: false,
    )
    window.title = live ? "Cleanup pill — live sequence" : "Cleanup pill — variants"
    window.contentView = root
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)

    print("CGWindowID:\(window.windowNumber)")
    fflush(stdout)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
