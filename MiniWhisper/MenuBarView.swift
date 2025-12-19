import SwiftUI

struct MenuBarView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("MiniWhisper").font(.headline)

      Divider()

      Button("Start Dictation") {
        // TODO: Start capture
      }.keyboardShortcut("d")

      Button("Settings...") {
        // TODO: Open settings
      }.keyboardShortcut(",")

      Divider()

      Button("Quit") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
    }.padding(8)
  }
}

#Preview { MenuBarView() }
