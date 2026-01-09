import SwiftUI

@main struct MiniWhisperApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene { Settings { Text("Settings placeholder").frame(width: 300, height: 200) } }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  private var settings: SettingsStore!
  private var recording: RecordingStore!
  private var menuBarController: MenuBarController!

  func applicationDidFinishLaunching(_ notification: Notification) {
    settings = SettingsStore()
    recording = RecordingStore()
    menuBarController = MenuBarController(settings: settings, recording: recording)
  }
}
