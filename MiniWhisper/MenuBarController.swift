import AudioCapture
import SwiftUI

// MARK: - Icon Selection

func iconSymbolName(status: RecordingStatus, micStatus: MicPermissionStatus) -> String {
  switch status {
  case .recording: return "record.circle.fill"
  case .processing: return "ellipsis.circle"
  case .idle:
    if micStatus == .granted { return "waveform" } else { return "waveform.badge.exclamationmark" }
  }
}

// MARK: - MenuBarController

@MainActor final class MenuBarController {
  private var statusItem: NSStatusItem?
  private let settings: SettingsStore
  private let recording: RecordingStore

  init(settings: SettingsStore, recording: RecordingStore) {
    self.settings = settings
    self.recording = recording
    setupStatusItem()
    observeRecordingChanges()
  }

  private func setupStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem?.button?.setAccessibilityIdentifier("MiniWhisperStatusItem")
    statusItem?.menu = buildMenu()
    updateIcon()
  }

  private func observeRecordingChanges() {
    withObservationTracking {
      _ = self.recording.status
      _ = self.recording.micStatus
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.observeRecordingChanges()
        self.updateIcon()
      }
    }
  }

  private func updateIcon() {
    let symbolName = iconSymbolName(status: recording.status, micStatus: recording.micStatus)
    statusItem?.button?.image = NSImage(
      systemSymbolName: symbolName, accessibilityDescription: "MiniWhisper")
  }

  func rebuildMenu() { statusItem?.menu = buildMenu() }

  private func buildMenu() -> NSMenu {
    let menu = NSMenu()

    let headerItem = NSMenuItem()
    let headerView = NSHostingView(rootView: MenuHeaderView(recording: recording))
    headerView.frame.size = headerView.fittingSize
    headerItem.view = headerView
    menu.addItem(headerItem)

    menu.addItem(.separator())

    let dictationItem = NSMenuItem()
    let dictationView = NSHostingView(
      rootView: DictationRowView(
        recording: recording, onRebuildMenu: { [weak self] in self?.rebuildMenu() }))
    dictationView.frame.size = dictationView.fittingSize
    dictationItem.view = dictationView
    menu.addItem(dictationItem)

    let settingsItem = NSMenuItem(title: "Settings...", action: nil, keyEquivalent: ",")
    menu.addItem(settingsItem)

    menu.addItem(.separator())

    let quitItem = NSMenuItem(
      title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    menu.addItem(quitItem)

    return menu
  }
}

// MARK: - Menu Views

struct MenuHeaderView: View {
  var recording: RecordingStore

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("MiniWhisper").font(.headline)
      Text(statusText).font(.subheadline).foregroundStyle(.secondary)
    }.padding(.horizontal, 14).padding(.vertical, 8)
  }

  private var statusText: String {
    switch recording.micStatus {
    case .granted:
      switch recording.status {
      case .idle: "✓ Ready"
      case .recording: "🔴 Recording..."
      case .processing: "⏳ Processing..."
      }
    case .denied, .undetermined: "⚠ Needs Mic Access"
    }
  }
}

struct DictationRowView: View {
  var recording: RecordingStore
  var onRebuildMenu: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Text("Start Dictation").opacity(recording.micStatus == .granted ? 1 : 0.4)

      Spacer()

      if recording.micStatus == .granted {
        Text("⌘D").foregroundStyle(.secondary)
      } else {
        Button {
          Task {
            await recording.requestMicAccess()
            onRebuildMenu()
          }
        } label: {
          Image(systemName: "mic").foregroundStyle(.white).padding(4).background(
            Color.orange, in: RoundedRectangle(cornerRadius: 4))
        }.buttonStyle(.plain)
      }
    }.padding(.horizontal, 14).padding(.vertical, 6).frame(minWidth: 180).contentShape(Rectangle())
  }
}
