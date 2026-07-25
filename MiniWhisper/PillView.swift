import ComposableArchitecture
import SwiftUI

struct PillView: View {
  private enum PresentationKind: Equatable {
    case hidden
    case recording
    case transcribing
    case noSpeechDetected
    case copiedToClipboard
  }

  @Bindable var store: StoreOf<PillFeature>
  @State private var bounceScale = 1.0

  var body: some View {
    ZStack {
      if let presentation = store.presentation {
        content(for: presentation).padding(.horizontal, 15).frame(height: 46).background(
          .regularMaterial, in: Capsule()
        ).overlay { Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5) }.shadow(
          color: .black.opacity(0.24), radius: 12, y: 5
        ).scaleEffect(bounceScale).opacity(store.isFadingOut ? 0 : 1).transition(
          .opacity.combined(with: .scale(scale: 0.96)))
      }
    }.frame(width: 420, height: 76).animation(.easeOut(duration: 0.16), value: presentationKind)
      .animation(.easeIn(duration: 0.18), value: store.isFadingOut).task(id: store.bounceCount) {
        guard store.bounceCount > 0 else { return }
        withAnimation(.easeOut(duration: 0.12)) { bounceScale = 1.055 }
        do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
        withAnimation(.easeInOut(duration: 0.13)) { bounceScale = 1 }
      }
  }

  private var presentationKind: PresentationKind {
    switch store.presentation {
    case .recording: .recording
    case .transcribing: .transcribing
    case .notice(.noSpeechDetected): .noSpeechDetected
    case .notice(.copiedToClipboard): .copiedToClipboard
    case nil: .hidden
    }
  }

  @ViewBuilder private func content(for presentation: PillFeature.State.Presentation) -> some View {
    switch presentation {
    case .recording(let recording):
      HStack(spacing: 10) {
        Circle().fill(Color(red: 0.95, green: 0.23, blue: 0.24)).frame(width: 9, height: 9).shadow(
          color: .red.opacity(0.45), radius: 3
        ).opacity(recording.isLive ? 1 : 0).animation(
          .easeOut(duration: 0.15), value: recording.isLive)
        AudioLevelBars(level: recording.level)
        Text(recording.inputDeviceName).font(.system(size: 13, weight: .medium)).lineLimit(1)
          .truncationMode(.middle).foregroundStyle(.primary)
      }
    case .transcribing:
      HStack(spacing: 9) {
        PulsingDot()
        Text("Transcribing…").font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
      }
    case .notice(.noSpeechDetected):
      Text("No speech detected").font(.system(size: 13, weight: .medium)).foregroundStyle(
        .secondary)
    case .notice(.copiedToClipboard):
      Text("Copied — ⌘V to paste").font(.system(size: 13, weight: .medium)).foregroundStyle(
        .primary)
    }
  }
}

private struct AudioLevelBars: View {
  var level: Float

  private let maximumHeights: [CGFloat] = [8, 14, 19, 14, 8]

  var body: some View {
    HStack(spacing: 2.5) {
      ForEach(maximumHeights.indices, id: \.self) { index in
        Capsule().fill(.primary.opacity(0.78)).frame(
          width: 2.5, height: barHeight(maximum: maximumHeights[index], index: index))
      }
    }.frame(width: 22.5, height: 20).animation(.linear(duration: 0.08), value: level)
  }

  private func barHeight(maximum: CGFloat, index: Int) -> CGFloat {
    let variation: Float = index.isMultiple(of: 2) ? 0.82 : 1
    return max(3, maximum * CGFloat(min(level * 1.35 * variation, 1)))
  }
}

private struct PulsingDot: View {
  @State private var isPulsing = false

  var body: some View {
    Circle().fill(Color(red: 0.20, green: 0.53, blue: 1)).frame(width: 9, height: 9).shadow(
      color: .blue.opacity(0.45), radius: 3
    ).scaleEffect(isPulsing ? 0.82 : 1).opacity(isPulsing ? 0.48 : 1).task {
      withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
        isPulsing = true
      }
    }
  }
}
