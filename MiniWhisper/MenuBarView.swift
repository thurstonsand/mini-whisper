import AudioCapture
import SwiftUI

struct MenuBarView: View {
  var appState: AppState

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("MiniWhisper").font(.headline)

      Text(statusText).font(.subheadline).foregroundStyle(.secondary)

      Divider()

      Button("Start Dictation") {
        // TODO: Start capture
      }.keyboardShortcut("d").disabled(appState.micStatus != .granted)

      Button("Settings...") {
        // TODO: Open settings
      }.keyboardShortcut(",")

      Divider()

      Button("Quit") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
    }.padding(8).task {
      if appState.micStatus == .undetermined { await appState.requestMicAccess() }
    }
  }

  private var statusText: String {
    switch appState.micStatus {
    case .granted: "✓ Ready"
    case .denied: "⚠ Needs Mic Access"
    case .undetermined: "Checking..."
    }
  }
}

#Preview { MenuBarView(appState: AppState()) }
