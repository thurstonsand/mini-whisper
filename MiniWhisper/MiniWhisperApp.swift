import SwiftUI

@main struct MiniWhisperApp: App {
  @State private var appState = AppState()

  var body: some Scene {
    MenuBarExtra("MiniWhisper", systemImage: "waveform") { MenuBarView(appState: appState) }
  }
}
