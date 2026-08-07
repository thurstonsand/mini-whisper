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

  private enum PresentationKind: Equatable {
    case hidden
    case recording
    case transcribing
    case noSpeechDetected
    case copiedToClipboard
    case fieldContextUnavailable
  }

  @State private var bounceScale = 1.0

  private var presentationKind: PresentationKind {
    switch store.presentation {
    case .recording:
      .recording
    case .transcribing:
      .transcribing
    case .notice(.noSpeechDetected):
      .noSpeechDetected
    case .notice(.copiedToClipboard):
      .copiedToClipboard
    case .notice(.fieldContextUnavailable):
      .fieldContextUnavailable
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
    case .notice(.noSpeechDetected):
      SemanticText(
        "No speech detected", identifier: AccessibilityID.pillNotice, label: "Dictation notice",
      )
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(.secondary)
    case .notice(.copiedToClipboard):
      SemanticText(
        "Copied — ⌘V to paste", identifier: AccessibilityID.pillNotice, label: "Dictation notice",
      )
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(.primary)
    case .notice(.fieldContextUnavailable):
      SemanticText(
        "Pasted — could not collect surrounding context", identifier: AccessibilityID.pillNotice,
        label: "Dictation notice",
      )
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(.secondary)
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
    case .transcribing:
      EmptyView()
    case .notice(.noSpeechDetected):
      semanticLeaf(
        identifier: AccessibilityID.pillPhase, label: "Dictation phase",
        value: "No speech detected",
      )
    case .notice(.copiedToClipboard):
      semanticLeaf(identifier: AccessibilityID.pillPhase, label: "Dictation phase", value: "Copied")
    case .notice(.fieldContextUnavailable):
      semanticLeaf(
        identifier: AccessibilityID.pillPhase, label: "Dictation phase",
        value: "Pasted without field context",
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

  var body: some View {
    Circle()
      .fill(Color(red: 0.20, green: 0.53, blue: 1))
      .frame(width: 9, height: 9)
      .shadow(
        color: .blue.opacity(0.45), radius: 3,
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
