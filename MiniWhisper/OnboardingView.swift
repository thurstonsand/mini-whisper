import ASREngine
import AudioCapture
import ComposableArchitecture
import SwiftUI

struct OnboardingView: View {
  @Bindable var store: StoreOf<OnboardingFeature>
  @FocusState private var tryItFieldIsFocused: Bool

  var body: some View {
    Group {
      if store.isShowingWelcome {
        welcomeContent
      } else {
        HStack(spacing: 0) {
          stepRail
          Divider()
          VStack(alignment: .leading, spacing: 0) {
            stepContent.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
          }.padding(.horizontal, 42).padding(.vertical, 36)
        }
      }
    }.frame(width: 720, height: 500).background(.background).onChange(of: store.visibleStep) {
      _, step in tryItFieldIsFocused = step == .tryIt && store.step == .tryIt
    }
  }

  private var welcomeContent: some View {
    VStack(spacing: 0) {
      ZStack {
        RoundedRectangle(cornerRadius: 22).fill(Color.accentColor.opacity(0.12)).frame(
          width: 92, height: 92)
        Image(systemName: "mic.fill").font(.system(size: 42, weight: .semibold)).foregroundStyle(
          Color.accentColor)
      }
      Text("MiniWhisper").font(.system(size: 34, weight: .semibold)).padding(.top, 24)
      Text("Fast, accurate dictation that runs on your Mac.").font(.system(size: 16))
        .foregroundStyle(.secondary).padding(.top, 8)
      Text("Download the speech model in the background while you finish setup.").font(
        .system(size: 13)
      ).foregroundStyle(.secondary).lineLimit(1).padding(.top, 12)
      Button("Download Parakeet v2") { store.send(.downloadModel) }.buttonStyle(.borderedProminent)
        .controlSize(.large).disabled(store.isRecordingModelDownloadConsent).padding(.top, 30)
      if let failureMessage = store.failureMessage {
        Label(failureMessage, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12))
          .foregroundStyle(.red).padding(.top, 16)
      }
    }.frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var stepRail: some View {
    VStack(alignment: .leading, spacing: 0) {
      Image(systemName: "mic.fill").font(.system(size: 25, weight: .semibold)).foregroundStyle(
        Color.accentColor)
      Text("MiniWhisper").font(.system(size: 19, weight: .semibold)).padding(.top, 10)
      Text("fast and accurate dictation").font(.system(size: 12)).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true).padding(.top, 3)

      VStack(alignment: .leading, spacing: 17) {
        railItem("Permissions", step: .permissions, symbol: "lock.shield")
        railItem("Speech Model", step: .model, symbol: "cpu")
        railItem("Try It", step: .tryIt, symbol: "checkmark.bubble")
      }.padding(.top, 38)

      Spacer()
    }.padding(.horizontal, 24).padding(.vertical, 30).frame(width: 210).background(
      Color(nsColor: .controlBackgroundColor).opacity(0.62))
  }

  private func railItem(_ title: String, step: OnboardingStep, symbol: String) -> some View {
    let isCurrent = store.visibleStep == step || (store.visibleStep == .ready && step == .tryIt)
    let isComplete =
      switch step {
      case .permissions: store.snapshot.permissions.allGranted
      case .model: store.snapshot.engineReadiness == .ready
      case .tryIt, .ready: store.snapshot.isCompleted
      }
    return Button {
      store.send(.navigate(step))
    } label: {
      HStack(spacing: 10) {
        Image(systemName: isComplete ? "checkmark.circle.fill" : symbol).frame(width: 18)
          .foregroundStyle(
            isComplete ? Color.green : isCurrent ? Color.accentColor : Color.secondary)
        Text(title).font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
          .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
        Spacer()
        if step == .model { compactModelProgress }
      }.contentShape(Rectangle())
    }.buttonStyle(.plain).focusEffectDisabled()
  }

  @ViewBuilder private var compactModelProgress: some View {
    switch store.snapshot.engineReadiness {
    case .downloading(let fraction):
      Text("\(Int(fraction * 100))%").font(.system(size: 10)).monospacedDigit().foregroundStyle(
        .secondary)
    case .compiling, .prewarming: ProgressView().controlSize(.mini)
    case .modelMissing, .ready, .failed: EmptyView()
    }
  }

  @ViewBuilder private var stepContent: some View {
    switch store.visibleStep {
    case .permissions: permissionsContent
    case .model: modelContent
    case .tryIt: tryItContent
    case .ready: readyContent
    }
  }

  private var permissionsContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      stepSymbol("lock.shield")
      Text("We need access to a few things first").font(.system(size: 28, weight: .semibold))
        .padding(.top, 20)
      Text("macOS will prompt you for each.").font(.system(size: 14)).foregroundStyle(.secondary)
        .lineLimit(1).frame(height: 58, alignment: .topLeading).padding(.top, 10)

      VStack(spacing: 0) {
        permissionRow(
          .inputMonitoring, title: "Input Monitoring", symbol: "keyboard",
          explanation: "Trigger MiniWhisper from anywhere")
        Divider()
        permissionRow(
          .microphone, title: "Microphone", symbol: "waveform",
          explanation: "Hear your beautiful voice")
        Divider()
        permissionRow(
          .pasteAccess, title: "Paste Access", symbol: "text.cursor",
          explanation: "Types the transcript at your cursor.")
      }.frame(maxWidth: .infinity, minHeight: 162, maxHeight: 162).background(
        Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 9)
      ).padding(.top, 24)
    }
  }

  private func permissionRow(
    _ permission: OnboardingPermission, title: String, symbol: String, explanation: String
  ) -> some View {
    let isGranted = store.snapshot.permissions.isGranted(permission)
    let ownsAction = store.activePermission == permission
    return HStack(spacing: 12) {
      Image(systemName: isGranted ? "checkmark.circle.fill" : symbol).font(.system(size: 15))
        .foregroundStyle(isGranted ? Color.green : Color.accentColor).frame(width: 20)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.system(size: 13, weight: .medium))
        Text(explanation).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(
          horizontal: false, vertical: true)
      }
      Spacer(minLength: 12)
      let showsSettings =
        store.isRevisitingPermissions || store.state.needsSystemSettings(for: permission)
      if isGranted {
        Text("Granted").font(.system(size: 12, weight: .medium)).foregroundStyle(.green)
      } else if ownsAction, store.state.needsRestart(for: permission) {
        Button("Restart MiniWhisper") { store.send(.restartApplication) }
      } else if ownsAction, showsSettings {
        Button("Open Settings") { store.send(.openSystemSettings(permission)) }
      } else if ownsAction {
        Button(store.requestingPermission == permission ? "Waiting…" : "Grant") {
          store.send(.requestPermission(permission))
        }.buttonStyle(.borderedProminent).disabled(store.requestingPermission != nil)
      }
    }.controlSize(.small).padding(.horizontal, 14).padding(.vertical, 9)
  }

  private var modelContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      stepSymbol("cpu")
      Text("Prepare Parakeet v2").font(.system(size: 28, weight: .semibold)).padding(.top, 20)
      Text("Downloads once (~450 MB), then everything runs on this Mac.").font(.system(size: 14))
        .foregroundStyle(.secondary).lineLimit(1).frame(
          maxWidth: 430, minHeight: 58, maxHeight: 58, alignment: .topLeading
        ).padding(.top, 10)

      VStack(alignment: .leading, spacing: 10) { modelCardContent }.padding(18).frame(
        maxWidth: .infinity, minHeight: 162, maxHeight: 162, alignment: .topLeading
      ).background(
        Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 9)
      ).padding(.top, 24)
    }
  }

  @ViewBuilder private var modelCardContent: some View {
    switch store.snapshot.engineReadiness {
    case .downloading(let fraction):
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("Downloading model").font(.system(size: 13, weight: .medium))
          Spacer()
          Text("\(Int(fraction * 100))%").monospacedDigit().foregroundStyle(.secondary)
        }
        ProgressView(value: fraction).progressViewStyle(.linear)
      }
    case .compiling: progressRow("Compiling Core ML models…")
    case .prewarming:
      VStack(alignment: .leading, spacing: 8) {
        progressRow("Optimizing for this Mac…")
        Text("The first specialization can take about 3–4 minutes. Keep MiniWhisper open.").font(
          .system(size: 12)
        ).foregroundStyle(.secondary)
      }
    case .modelMissing, .failed:
      Label("About 450 MB · downloaded once", systemImage: "internaldrive").font(.system(size: 12))
        .foregroundStyle(.secondary)
    case .ready:
      Label("Parakeet v2 is ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
    }
  }

  private var tryItContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      stepSymbol("quote.bubble")
      Text("Give it a try").font(.system(size: 28, weight: .semibold)).padding(.top, 20)
      Text(
        "Focus the text box below, hold Right Option while you speak, then release. Or double-tap Right Option to keep recording until you tap it again."
      ).font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(3).frame(
        height: 58, alignment: .topLeading
      ).padding(.top, 10)

      VStack(alignment: .leading, spacing: 10) { tryItCardContent }.padding(14).frame(
        maxWidth: .infinity, minHeight: 162, maxHeight: 162, alignment: .topLeading
      ).background(
        Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 9)
      ).padding(.top, 24)
    }
  }

  @ViewBuilder private var tryItCardContent: some View {
    switch store.step {
    case .permissions:
      unavailableContent(
        "Grant all 3 permissions and wait for the speech model to try it.", symbol: "lock.shield")
    case .model:
      unavailableContent(
        "Wait for the speech model to finish before trying a dictation.", symbol: "cpu")
    case .tryIt:
      TextEditor(
        text: Binding(get: { store.tryItText }, set: { store.send(.tryItTextChanged($0)) })
      ).font(.system(size: 15)).scrollContentBackground(.hidden).padding(8).frame(height: 96)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
          RoundedRectangle(cornerRadius: 7).strokeBorder(
            tryItFieldIsFocused ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
        }.focused($tryItFieldIsFocused).onAppear { tryItFieldIsFocused = true }
      Text("Right ⌥").font(.system(size: 12, weight: .medium)).padding(.horizontal, 8).padding(
        .vertical, 4
      ).background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
    case .ready:
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "checkmark.circle.fill").font(.system(size: 17)).foregroundStyle(
          Color.green
        ).frame(width: 22)
        VStack(alignment: .leading, spacing: 5) {
          Text("Your test dictation is complete").font(.system(size: 13, weight: .semibold))
          Text("MiniWhisper is ready to use in any text field.").font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private var readyContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      ZStack {
        Circle().fill(Color.green.opacity(0.14)).frame(width: 58, height: 58)
        Image(systemName: "checkmark").font(.system(size: 25, weight: .bold)).foregroundStyle(
          .green)
      }
      Text("Ready").font(.system(size: 32, weight: .semibold)).padding(.top, 20)
      Text(
        "Your first dictation made the full trip. Hold Right Option in any text field and speak."
      ).font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(3).frame(
        maxWidth: 420, alignment: .leading
      ).padding(.top, 10)
      if !store.tryItText.isEmpty {
        Text("“\(store.tryItText)”").font(.system(size: 14)).italic().lineLimit(3).padding(.top, 24)
      }
    }
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let failureMessage = store.failureMessage {
        Label(failureMessage, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12))
          .foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        if store.canSkip {
          Button("Skip") { store.send(.skip) }.buttonStyle(.plain).foregroundStyle(.secondary)
            .disabled(store.isMarkingCompletion)
        }
        Spacer()
        footerButtons
      }
    }
  }

  @ViewBuilder private var footerButtons: some View {
    switch store.visibleStep {
    case .permissions:
      if store.state.needsRestart(for: .inputMonitoring) {
        Text("Enable Input Monitoring before restarting.").font(.system(size: 11)).foregroundStyle(
          .secondary)
      } else {
        Text("Continue after granting all 3").font(.system(size: 12)).foregroundStyle(.secondary)
      }
    case .model:
      if !store.modelSetupIsInProgress, store.snapshot.engineReadiness != .ready {
        Button(
          store.snapshot.engineReadiness.isFailure ? "Retry Model Setup" : "Download & Prepare"
        ) { store.send(.setupModel) }.buttonStyle(.borderedProminent)
      }
    case .tryIt:
      if store.step == .tryIt {
        Text("Speak to complete…").font(.system(size: 12)).foregroundStyle(.secondary)
      } else if store.step != .ready {
        Text("Complete the earlier steps to try a dictation").font(.system(size: 12))
          .foregroundStyle(.secondary)
      }
    case .ready: Button("Start Dictating") { store.send(.finish) }.buttonStyle(.borderedProminent)
    }
  }

  private func stepSymbol(_ symbol: String) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: 13).fill(Color.accentColor.opacity(0.12)).frame(
        width: 58, height: 58)
      Image(systemName: symbol).font(.system(size: 24, weight: .medium)).foregroundStyle(
        Color.accentColor)
    }
  }

  private func progressRow(_ title: String) -> some View {
    HStack(spacing: 10) {
      ProgressView().controlSize(.small)
      Text(title).font(.system(size: 13, weight: .medium))
    }
  }

  private func unavailableContent(_ message: String, symbol: String) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(Color.accentColor).frame(
        width: 22)
      Text(message).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(
        horizontal: false, vertical: true)
    }
  }
}

extension EngineReadiness {
  fileprivate var isFailure: Bool {
    if case .failed = self { return true }
    return false
  }
}
