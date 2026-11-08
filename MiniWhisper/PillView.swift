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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 38)
        .background(.thickMaterial, in: .capsule)
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
    .animation(.easeOut(duration: 0.16), value: store.destination)
    .animation(.easeOut(duration: 0.16), value: store.submits)
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

  @ViewBuilder private var submits: some View {
    if store.submits {
      Label("Then submit", systemImage: "return")
        .labelStyle(.titleAndIcon)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize()
        .accessibilityLabel("Submits after delivery")
        .accessibilityIdentifier(AccessibilityID.pillSubmits)
    }
  }

  @ViewBuilder private var destination: some View {
    if let destination = store.destination {
      HStack(spacing: 6) {
        Image(systemName: "arrow.right")
          .accessibilityHidden(true)
        SemanticText(
          destination, identifier: AccessibilityID.pillDestination, label: "Delivers to",
        )
        .lineLimit(1)
        .truncationMode(.middle)
      }
      .font(.callout)
      .foregroundStyle(.primary)
    }
  }

  @ViewBuilder private func content(for presentation: PillFeature.State.Presentation) -> some View {
    switch presentation {
    case let .recording(recording):
      HStack(spacing: 10) {
        Circle()
          .fill(.red)
          .frame(width: 6, height: 6)
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
        .font(.callout)
        .lineLimit(1)
        .truncationMode(.middle)
        .foregroundStyle(.secondary)
      }
    case .transcribing:
      VStack(spacing: 6) {
        HStack(spacing: 9) {
          ProgressView().controlSize(.mini).accessibilityHidden(true)
          SemanticText(
            "Transcribing…", identifier: AccessibilityID.pillPhase, label: "Dictation phase",
            value: "Transcribing",
          )
          .font(.callout)
          .foregroundStyle(.primary)
          submits
        }
        destination
      }
    case let .polishing(polishing):
      VStack(spacing: 6) {
        HStack(spacing: 9) {
          ProgressView().controlSize(.mini).accessibilityHidden(true)
          SemanticText(
            "Polishing…", identifier: AccessibilityID.pillPhase, label: "Dictation phase",
            value: "Polishing",
          )
          .font(.callout)
          .foregroundStyle(.primary)
          submits
          if polishing.isSkipRevealed {
            Divider().frame(height: 16)
            SemanticText(
              "Skip", identifier: AccessibilityID.pillSkipAffordance, label: "Skip cleanup",
              value: "\(polishing.skipComponents.joined(separator: " ")) to skip",
            )
            .font(.callout)
            .foregroundStyle(.primary)
            .fixedSize()
            Text(polishing.skipComponents.joined(separator: " "))
              .font(.callout)
              .padding(.horizontal, 5)
              .padding(.vertical, 2)
              .background(.fill.tertiary, in: .rect(cornerRadius: 3))
              .fixedSize()
              .accessibilityHidden(true)
          }
        }
        destination
      }
    case let .notice(notice):
      HStack(spacing: 9) {
        noticeSymbol(notice).accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 3) {
          Text(notice.content.text)
          if let detail = notice.content.detail {
            Text(detail)
              .font(.callout)
              .foregroundStyle(.secondary)
          }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(AccessibilityID.pillNotice)
        .accessibilityLabel("Dictation notice")
        .accessibilityValue(
          [notice.content.text, notice.content.detail].compactMap(\.self).joined(separator: "\n"),
        )
        .accessibilityAddTraits(.isStaticText)
      }
      .font(.callout)
      .foregroundStyle(.primary)
    }
  }

  @ViewBuilder private func noticeSymbol(_ notice: PillFeature.State.Presentation
    .Notice) -> some View
  {
    switch notice {
    case .copiedToClipboard,
         .noReceiver:
      Image(systemName: "clipboard").foregroundStyle(.secondary)
    case .cancelledSavedToHistory:
      Image(systemName: "xmark").foregroundStyle(.secondary)
    case .noSpeechDetected:
      Image(systemName: "waveform.slash").foregroundStyle(.secondary)
    case .noTranscriptToPaste:
      Image(systemName: "clipboard").foregroundStyle(.secondary)
    case .speechModelUnavailable:
      Image(systemName: "info.circle").foregroundStyle(.secondary)
    case .cleanupUnavailable,
         .dictionarySaveFailed:
      Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary)
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
