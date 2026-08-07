// Disposable mock-up of the proposed onboarding "Shortcut" step for ticket 31.
// Not an Xcode target, imports no MiniWhisper code, must not ship. Every value is invented.
//
//   swiftc -framework AppKit -framework SwiftUI \
//     spikes/onboarding-shortcut-mockup/OnboardingShortcutMockup.swift -o .build/onboarding-shortcut-mockup
//   .build/onboarding-shortcut-mockup a          # variants: a b c d e
//   .build/onboarding-shortcut-mockup c dark     # optional trailing appearance: light | dark

import AppKit
import SwiftUI

// MARK: - Variant

enum Variant: String, CaseIterable {
  case a // settings-style row: keycaps + Change… button
  case b // hero keycap: the keycap is the button; click starts the recorder in place
  case b2 // hero keycap mid-recording: same chip, live chord, Continue disabled
  case c // recorder-first: the card is a live recording well, default is the escape hatch
  case d // preset list: common candidates as radio rows + Custom…
  case e // two cards: keep the default vs choose your own
}

// MARK: - Keycaps (replica of HotkeyKeycaps)

struct Keycaps: View {
  let components: [String]
  var scale: CGFloat = 1
  var ringed = false

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
    .overlay {
      RoundedRectangle(cornerRadius: 7 * scale)
        .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
        .opacity(ringed ? 1 : 0)
    }
  }
}

// MARK: - Shared onboarding scaffold

struct MockWindow: View {
  let variant: Variant

  var body: some View {
    HStack(spacing: 0) {
      rail
      Divider()
      VStack(alignment: .leading, spacing: 0) {
        content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        footer
      }
      .padding(.horizontal, 42)
      .padding(.vertical, 36)
    }
    .frame(width: 720, height: 500)
    .background(.background)
  }

  private var rail: some View {
    VStack(alignment: .leading, spacing: 0) {
      Image(systemName: "mic.fill")
        .font(.system(size: 25, weight: .semibold))
        .foregroundStyle(Color.accentColor)
      Text("MiniWhisper Dev")
        .font(.system(size: 19, weight: .semibold))
        .padding(.top, 10)
      Text("fast and accurate dictation")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 3)
      VStack(alignment: .leading, spacing: 17) {
        railItem("Permissions", symbol: "lock.shield", state: .complete)
        railItem("Shortcut", symbol: "command", state: .current)
        railItem("Speech Model", symbol: "cpu", state: .pending, trailing: "42%")
        railItem("Try It", symbol: "checkmark.bubble", state: .pending)
      }.padding(.top, 38)
      Spacer()
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 30)
    .frame(width: 210, alignment: .leading)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.62))
  }

  private enum RailState { case complete, current, pending }

  private func railItem(
    _ title: String, symbol: String, state: RailState, trailing: String? = nil,
  ) -> some View {
    HStack(spacing: 10) {
      Image(systemName: state == .complete ? "checkmark.circle.fill" : symbol)
        .frame(width: 18)
        .foregroundStyle(
          state == .complete ? Color.green : state == .current ? Color.accentColor : Color.secondary,
        )
      Text(title)
        .font(.system(size: 12, weight: state == .current ? .semibold : .regular))
        .foregroundStyle(state == .current ? Color.primary : Color.secondary)
      Spacer()
      if let trailing {
        Text(trailing).font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
      }
    }
  }

  private func stepSymbol(_ symbol: String) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: 13).fill(Color.accentColor.opacity(0.12))
        .frame(width: 58, height: 58)
      Image(systemName: symbol).font(.system(size: 24, weight: .medium))
        .foregroundStyle(Color.accentColor)
    }
  }

  private func heading(_ title: String, _ summary: String) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      stepSymbol("command")
      Text(title)
        .font(.system(size: 28, weight: .semibold))
        .padding(.top, 20)
      Text(summary)
        .font(.system(size: 14))
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .frame(height: 58, alignment: .topLeading)
        .padding(.top, 10)
    }
  }

  private func card(minHeight: CGFloat = 162, @ViewBuilder _ content: () -> some View) -> some View {
    content()
      .frame(maxWidth: .infinity, minHeight: minHeight, maxHeight: minHeight)
      .background(
        Color(nsColor: .controlBackgroundColor).opacity(0.5),
        in: RoundedRectangle(cornerRadius: 9),
      )
      .padding(.top, 24)
  }

  // MARK: Variant content

  @ViewBuilder private var content: some View {
    switch variant {
    case .a: variantA
    case .b: variantB(recording: false)
    case .b2: variantB(recording: true)
    case .c: variantC
    case .d: variantD
    case .e: variantE
    }
  }

  @ViewBuilder private var footer: some View {
    HStack {
      Spacer()
      switch variant {
      case .a, .b, .d, .e:
        Button("Continue") {}.buttonStyle(.borderedProminent).controlSize(.regular)
      case .b2:
        Button("Continue") {}.buttonStyle(.borderedProminent).disabled(true)
      case .c:
        Button("Keep Right Option") {}
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)
        Button("Continue") {}.buttonStyle(.borderedProminent).disabled(true)
      }
    }
  }

  // A — the settings row, transplanted. Conservative: same card grammar as Permissions.
  private var variantA: some View {
    VStack(alignment: .leading, spacing: 0) {
      heading(
        "Pick your dictation shortcut",
        "Hold it to record, release to transcribe. Right Option stays out of the way of every other app.",
      )
      card {
        HStack(spacing: 12) {
          Image(systemName: "command")
            .font(.system(size: 15))
            .foregroundStyle(Color.accentColor)
            .frame(width: 20)
          VStack(alignment: .leading, spacing: 2) {
            Text("Activate").font(.system(size: 13, weight: .medium))
            Text("Hold to dictate, or double-tap to keep recording.")
              .font(.system(size: 11)).foregroundStyle(.secondary)
          }
          Spacer(minLength: 12)
          Keycaps(components: ["⌥ Opt →"])
          Button("Change…") {}
        }
        .padding(.horizontal, 18)
      }
    }
  }

  // B — hero keycap. The keycap is the button: click it and the same chip records in place,
  // exactly the settings row's contract. Only the primary binding lives here; the rest stay
  // in Settings.
  private func variantB(recording: Bool) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      heading(
        "Activating MiniWhisper",
        "Shortcut to start dictation.",
      )
      card {
        VStack(spacing: 14) {
          Keycaps(
            components: recording ? ["⌃ Ctrl →", "⇧ Shift →"] : ["⌥ Opt →"],
            scale: 1.8, ringed: recording,
          )
          Text(recording ? "Record your shortcut" : "Click the shortcut to change")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
      }
    }
  }

  // C — recorder-first. The card is live and waiting; keeping the default is the footer's escape.
  private var variantC: some View {
    VStack(alignment: .leading, spacing: 0) {
      heading(
        "Press your dictation shortcut",
        "Press the keys you want to hold while dictating. Modifier-only chords work best.",
      )
      card {
        VStack(spacing: 12) {
          Text("Press a key combination…")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.secondary)
          Keycaps(components: ["⌃ Ctrl →", "⇧ Shift →"], scale: 1.4)
            .opacity(0.85)
          Text("Release every key to set it. Esc cancels.")
            .font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .overlay {
          RoundedRectangle(cornerRadius: 9)
            .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 2)
        }
      }
    }
  }

  // D — preset radio list + Custom…, in the Permissions card's row grammar.
  private var variantD: some View {
    VStack(alignment: .leading, spacing: 0) {
      heading(
        "Pick your dictation shortcut",
        "Hold it to record, release to transcribe. All of these stay out of the way of typing.",
      )
      card(minHeight: 186) {
        VStack(spacing: 0) {
          presetRow("Right Option", keycaps: ["⌥ Opt →"], selected: true, note: "Recommended")
          Divider().padding(.leading, 44)
          presetRow("Right Command", keycaps: ["⌘ Cmd →"], selected: false, note: nil)
          Divider().padding(.leading, 44)
          presetRow("Fn Globe", keycaps: ["🌐 Fn"], selected: false, note: nil)
          Divider().padding(.leading, 44)
          HStack(spacing: 12) {
            Image(systemName: "circle")
              .font(.system(size: 14)).foregroundStyle(.secondary).frame(width: 20)
            Text("Custom…").font(.system(size: 13))
            Spacer()
            Text("Record any chord").font(.system(size: 11)).foregroundStyle(.tertiary)
          }
          .padding(.horizontal, 14).padding(.vertical, 9)
        }
        .padding(.vertical, 4)
      }
    }
  }

  private func presetRow(
    _ title: String, keycaps: [String], selected: Bool, note: String?,
  ) -> some View {
    HStack(spacing: 12) {
      Image(systemName: selected ? "checkmark.circle.fill" : "circle")
        .font(.system(size: 14))
        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
        .frame(width: 20)
      Text(title).font(.system(size: 13, weight: selected ? .medium : .regular))
      if let note {
        Text(note).font(.system(size: 11)).foregroundStyle(.secondary)
      }
      Spacer()
      Keycaps(components: keycaps)
    }
    .padding(.horizontal, 14).padding(.vertical, 9)
    .contentShape(Rectangle())
  }

  // E — two cards: keep vs choose. The fork is the whole page.
  private var variantE: some View {
    VStack(alignment: .leading, spacing: 0) {
      heading(
        "How will you start a dictation?",
        "One key starts every dictation — hold to record, release to transcribe.",
      )
      HStack(spacing: 14) {
        choiceCard(
          selected: true, symbol: "checkmark.circle.fill", title: "Keep Right Option",
          note: "Recommended. Stays out of the way of every other app.",
        ) {
          Keycaps(components: ["⌥ Opt →"], scale: 1.3)
        }
        choiceCard(
          selected: false, symbol: "record.circle", title: "Choose my own",
          note: "Press any chord — modifiers, or modifiers plus one key.",
        ) {
          Text("Click to record")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
        }
      }
      .frame(height: 186)
      .padding(.top, 24)
    }
  }

  private func choiceCard(
    selected: Bool, symbol: String, title: String, note: String,
    @ViewBuilder detail: () -> some View,
  ) -> some View {
    VStack(spacing: 10) {
      Image(systemName: symbol)
        .font(.system(size: 22))
        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
      Text(title).font(.system(size: 13, weight: .semibold))
      detail()
      Text(note)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      Color(nsColor: .controlBackgroundColor).opacity(0.5),
      in: RoundedRectangle(cornerRadius: 9),
    )
    .overlay {
      RoundedRectangle(cornerRadius: 9)
        .strokeBorder(
          selected ? Color.accentColor : Color.secondary.opacity(0.25),
          lineWidth: selected ? 2 : 1,
        )
    }
  }
}

// MARK: - Host

final class AppDelegate: NSObject, NSApplicationDelegate {
  var window: NSWindow!

  func applicationDidFinishLaunching(_: Notification) {
    let arguments = CommandLine.arguments.dropFirst()
    let variant = arguments.compactMap { Variant(rawValue: $0.lowercased()) }.first ?? .a
    if arguments.contains("dark") {
      NSApp.appearance = NSAppearance(named: .darkAqua)
    } else if arguments.contains("light") {
      NSApp.appearance = NSAppearance(named: .aqua)
    }
    window = NSWindow(
      contentRect: .zero, styleMask: [.titled, .fullSizeContentView], backing: .buffered,
      defer: false,
    )
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.contentView = NSHostingView(rootView: MockWindow(variant: variant))
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    print(window.windowNumber)
    fflush(stdout)
  }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
