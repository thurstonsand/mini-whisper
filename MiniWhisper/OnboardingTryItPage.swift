import AppSettings
import ComposableArchitecture
import HotkeyListener
import SwiftUI

// MARK: - OnboardingTryItPage

/// The one page whose card is only ever the real thing: an editable field the user dictates into.
/// Until the earlier steps are done it says which one is missing rather than pretending.
struct OnboardingTryItPage: View {
  // MARK: Internal

  let store: StoreOf<OnboardingFeature>
  var focus: FocusState<OnboardingFocus?>.Binding

  var body: some View {
    OnboardingStepPage(
      symbol: "quote.bubble",
      title: .init(
        text: title,
        identifier: AccessibilityID.onboardingTryItTitle,
        label: "Try it heading",
      ),
      summary: nil,
      summaryLineSpacing: 3,
      cardAlignment: .topLeading,
    ) {
      VStack(alignment: .leading, spacing: 10) { cardContent }
    }
    .animation(.easeInOut(duration: 0.2), value: store.step)
    .accessibilityIdentifier(AccessibilityID.onboardingTryIt)
    .accessibilityLabel("Try \(Channel.name)")
  }

  // MARK: Private

  @State private var mouseIsDown = false

  private var title: String {
    store.canTryDictation || !store.missingKeys.isEmpty
      ? "Give it a try" : "Set up dictation to try it"
  }

  private var addKeyTitle: String {
    store.missingKeys.count == 1 ? "Add \(store.missingKeys[0].provider.displayName) Key…" : "Add Keys…"
  }

  private var keyIsDown: Bool {
    switch store.practicePhase {
    case .holding,
         .secondPress:
      true
    default:
      false
    }
  }

  private var holdRecognized: Bool {
    switch store.practicePhase {
    case let .holding(startedAt),
         let .secondPress(startedAt):
      .seconds(ProcessInfo.processInfo.systemUptime) - startedAt
        >= HotkeyGestureMachine.Timing.standard.tapMaximumDuration
    default:
      false
    }
  }

  @ViewBuilder private var cardContent: some View {
    if !store.missingKeys.isEmpty {
      keylessRecovery
    } else {
      switch store.step {
      case .keys:
        unavailable("Add your keys to try a dictation.", symbol: "key")
      case .permissions:
        unavailable(
          "Grant both permissions and wait for the speech model to try it.", symbol: "lock.shield",
        )
      case .shortcut:
        unavailable(
          "Choose your shortcut and wait for the speech model to try it.",
          symbol: "command",
        )
      case .model:
        unavailable("Wait for the speech model to finish before trying a dictation.", symbol: "cpu")
      case .tryIt,
           .ready:
        editor
        practiceControls
      }
    }
  }

  private var keylessRecovery: some View {
    VStack(alignment: .leading, spacing: 12) {
      TextField(
        "Try dictation",
        text: .constant(""),
        prompt: Text(OnboardingCopy.tryItQuote),
        axis: .vertical,
      )
      .labelsHidden()
      .lineLimit(4, reservesSpace: true)
      .textFieldStyle(.roundedBorder)
      .disabled(true)
      .overlay(alignment: .bottomTrailing) {
        Label(
          "No \(store.missingKeys.map(\.provider.displayName).joined(separator: " or ")) key",
          systemImage: "key",
        )
        .font(.callout)
        .padding(6)
        .background(.regularMaterial, in: .rect(cornerRadius: 5))
        .padding(4)
      }
      Button { store.send(.navigate(.keys)) } label: {
        HStack {
          Label(addKeyTitle, systemImage: "key")
          Spacer()
          Image(systemName: "chevron.right")
        }
        .frame(minHeight: 26)
      }
      .buttonStyle(.borderedProminent)
      .focused(focus, equals: .tryItAddKey)
      .keyboardShortcut(.defaultAction)
      .accessibilityLabel(addKeyTitle)
      OnboardingKeylessChoices(store: store, focus: focus)
    }
  }

  private var editor: some View {
    TextField(
      text: Binding(get: { store.tryItText }, set: { store.send(.tryItTextChanged($0)) }),
      prompt: Text(OnboardingCopy.tryItQuote),
      axis: .vertical,
    ) {
      Text("Try dictation")
    }
    .labelsHidden()
    .textFieldStyle(.plain)
    .font(.body)
    .lineLimit(4, reservesSpace: true)
    .padding(8)
    .frame(height: 96, alignment: .topLeading)
    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
    .overlay {
      RoundedRectangle(cornerRadius: 7).strokeBorder(
        focus.wrappedValue == .tryItEditor ? Color.accentColor : Color.secondary.opacity(0.3),
        lineWidth: 1,
      )
    }
    .focused(focus, equals: .tryItEditor)
    .accessibilityIdentifier(AccessibilityID.onboardingTryItText)
    .accessibilityLabel("Try dictation")
    // Focus is claimed when the field exists, not when the state that summons it changes: a
    // @FocusState assignment aimed at a view SwiftUI has not built yet lands nowhere, and the
    // yield puts this after AppKit has chosen its own first responder.
    .task {
      await Task.yield()
      focus.wrappedValue = .tryItEditor
    }
  }

  private var practiceControls: some View {
    HStack(spacing: 12) {
      Button {} label: {
        HotkeyKeycaps(components: store.hotkeys.first?.displayComponents ?? ["Record"], scale: 1.5)
          .scaleEffect(keyIsDown ? 0.94 : 1)
      }
      .buttonStyle(.bordered)
      .focusable(false)
      .simultaneousGesture(DragGesture(minimumDistance: 0)
        .onChanged { _ in
          guard !mouseIsDown else {
            return
          }
          mouseIsDown = true
          focus.wrappedValue = .tryItEditor
          store.send(.practiceKeyChanged(
            true, .seconds(NSApp.currentEvent!.timestamp),
          ))
        }
        .onEnded { _ in
          mouseIsDown = false
          store.send(.practiceKeyChanged(
            false, .seconds(NSApp.currentEvent!.timestamp),
          ))
        })
      .accessibilityIdentifier("miniwhisper.onboarding.try-it.key")
      .accessibilityLabel(store.hotkeys.first?.displayName ?? "Record")
      .frame(width: 110, height: 64)
      .overlay(alignment: .topTrailing) {
        if store.practicePhase == .latched {
          Image(systemName: "lock.fill")
            .foregroundStyle(Color.accentColor)
        }
      }
      TimelineView(.animation(minimumInterval: 0.05, paused: !keyIsDown)) { _ in
        gestureTile("Hold", symbol: "hand.point.up.left.fill", active: holdRecognized)
      }
      gestureTile("Double-tap", symbol: "hand.tap.fill", active: store.practicePhase == .latched)
    }
  }

  private func gestureTile(_ title: String, symbol: String, active: Bool) -> some View {
    VStack(spacing: 8) {
      Image(systemName: symbol).font(.title2).accessibilityHidden(true)
      SemanticText(
        title, identifier: "miniwhisper.onboarding.gesture.\(title)",
        label: title, value: active ? "Active" : "Idle",
      ).font(.callout)
    }
    .foregroundStyle(active ? Color.accentColor : .secondary)
    .frame(maxWidth: .infinity, minHeight: 64)
    .background(.quaternary, in: .rect(cornerRadius: 8))
  }

  private func unavailable(_ message: String, symbol: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(Color.accentColor).frame(
        width: 22,
      )
      Text(message).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(
        horizontal: false, vertical: true,
      )
    }
    .accessibilityElement(children: .ignore)
    .accessibilityIdentifier(AccessibilityID.onboardingTryItAvailability)
    .accessibilityLabel("Try dictation availability")
    .accessibilityValue(message)
  }
}
