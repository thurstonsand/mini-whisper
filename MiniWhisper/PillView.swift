import ComposableArchitecture
import SwiftUI

// MARK: - PillView

struct PillView: View {
  // MARK: Internal

  @Bindable var store: StoreOf<PillFeature>

  var body: some View {
    ZStack {
      if let presentation = store.presentation {
        ZStack {
          content(for: presentation)
          semanticState(for: presentation)
        }
        .accessibilityElement(children: .contain)
        .padding(.horizontal, 15)
        .frame(height: 46)
        .background(.regularMaterial, in: Capsule())
        .overlay {
          Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5).accessibilityHidden(true)
        }
        .shadow(color: .black.opacity(0.24), radius: 12, y: 5)
        .scaleEffect(bounceScale)
        .opacity(
          store.isFadingOut ? 0 : 1,
        )
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
      }
    }
    .frame(width: 420, height: 76)
    .animation(.easeOut(duration: 0.16), value: presentationKind)
    .animation(.easeIn(duration: 0.18), value: store.isFadingOut)
    .task(id: store.bounceCount) {
      guard store.bounceCount > 0 else {
        return
      }
      withAnimation(.easeOut(duration: 0.12)) { bounceScale = 1.055 }
      do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
      withAnimation(.easeInOut(duration: 0.13)) { bounceScale = 1 }
    }
  }

  // MARK: Private

  /// What is on screen, with the live data left out: a recording's level changes many times a
  /// second, and animating on it would restart the transition every frame.
  private enum PresentationKind: Equatable {
    case hidden
    case recording
    case transcribing
    case polishing(isSkipRevealed: Bool)
    case notice(PillFeature.State.Presentation.Notice)
  }

  @State private var bounceScale = 1.0

  private var presentationKind: PresentationKind {
    switch store.presentation {
    case .recording:
      .recording
    case .transcribing:
      .transcribing
    case let .polishing(polishing):
      .polishing(isSkipRevealed: polishing.isSkipRevealed)
    case let .notice(notice):
      .notice(notice)
    case nil:
      .hidden
    }
  }

  @ViewBuilder private func content(for presentation: PillFeature.State.Presentation) -> some View {
    switch presentation {
    case let .recording(recording):
      HStack(spacing: 10) {
        Circle()
          .fill(Color(red: 0.95, green: 0.23, blue: 0.24))
          .frame(width: 9, height: 9)
          .shadow(
            color: .red.opacity(0.45), radius: 3,
          )
          .opacity(recording.isLive ? 1 : 0)
          .animation(
            .easeOut(duration: 0.15), value: recording.isLive,
          )
          .accessibilityHidden(true)
        AudioLevelBars(level: recording.level).accessibilityHidden(true)
        SemanticText(
          recording.inputDeviceName, identifier: AccessibilityID.pillInputDevice,
          label: "Input device",
        )
        .font(.system(size: 13, weight: .medium))
        .lineLimit(1)
        .truncationMode(.middle)
        .foregroundStyle(.primary)
      }
    case .transcribing:
      HStack(spacing: 9) {
        PulsingDot().accessibilityHidden(true)
        SemanticText(
          "Transcribing…", identifier: AccessibilityID.pillPhase, label: "Dictation phase",
          value: "Transcribing",
        )
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.primary)
      }
    case let .polishing(polishing):
      HStack(spacing: 9) {
        PulsingDot(color: .cleanup, glow: .purple).accessibilityHidden(true)
        SemanticText(
          "Polishing…", identifier: AccessibilityID.pillPhase, label: "Dictation phase",
          value: "Polishing",
        )
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.primary)
        if polishing.isSkipRevealed {
          Spacer().frame(width: 2)
          HotkeyKeycaps(components: polishing.skipComponents, scale: 0.85)
            .accessibilityHidden(true)
          SemanticText(
            "to skip", identifier: AccessibilityID.pillSkipAffordance, label: "Skip cleanup",
            value: "\(polishing.skipComponents.joined(separator: " ")) to skip",
          )
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(.secondary)
        }
      }
    case let .notice(notice):
      SemanticText(
        notice.content.text, identifier: AccessibilityID.pillNotice,
        label: "Dictation notice",
      )
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(notice.content
        .isSubdued ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
    }
  }

  @ViewBuilder private func semanticState(
    for presentation: PillFeature.State.Presentation,
  ) -> some View {
    switch presentation {
    case let .recording(recording):
      semanticLeaf(
        identifier: AccessibilityID.pillPhase, label: "Dictation phase", value: "Recording",
      )
      semanticLeaf(
        identifier: AccessibilityID.pillCaptureStatus, label: "Capture status",
        value: recording.isLive ? "Live" : "Starting",
      )
      semanticLeaf(
        identifier: AccessibilityID.pillAudioLevel, label: "Input level",
        value: "\(store.accessibilityLevel)%",
      )
    case .polishing,
         .transcribing:
      EmptyView()
    case let .notice(notice):
      semanticLeaf(
        identifier: AccessibilityID.pillPhase, label: "Dictation phase",
        value: notice.content.phase,
      )
    }
  }

  private func semanticLeaf(identifier: String, label: String, value: String) -> some View {
    // Custom shapes expose no AXValue, while zero-sized views are pruned, so retain a rendered 1×1
    // Text.
    SemanticText(value, identifier: identifier, label: label)
      .font(.system(size: 1))
      .foregroundStyle(.clear)
      .frame(width: 1, height: 1)
      .clipped()
  }
}

// MARK: - PulsingDot

private struct PulsingDot: View {
  // MARK: Internal

  var color = Color.dictation
  var glow = Color.blue

  var body: some View {
    Circle()
      .fill(color)
      .frame(width: 9, height: 9)
      .shadow(
        color: glow.opacity(0.45), radius: 3,
      )
      .scaleEffect(isPulsing ? 0.82 : 1)
      .opacity(isPulsing ? 0.48 : 1)
      .task {
        withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
          isPulsing = true
        }
      }
  }

  // MARK: Private

  @State private var isPulsing = false
}

// MARK: - Pill phase colours

private extension Color {
  /// The engine leg's blue and the network leg's purple, as chosen on real pixels in the pill
  /// mock-up spike.
  static let dictation = Color(red: 0.20, green: 0.53, blue: 1)
  static let cleanup = Color(red: 0.62, green: 0.40, blue: 0.95)
}
