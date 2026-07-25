import ComposableArchitecture
import HotkeyListener
import OSLog
import SwiftUI

@main struct MiniWhisperApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene { Settings { EmptyView() } }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  private let logger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "lifecycle")
  private let performanceLogger = Logger(
    subsystem: "com.thurstonsand.MiniWhisper", category: "performance")
  private let store = Store(initialState: AppFeature.State()) { AppFeature() }

  private var menuBarController: MenuBarController!
  private var pillPanelController: PillPanelController!

  func applicationDidFinishLaunching(_ notification: Notification) {
    logger.notice("App started; structured logging ready")
    menuBarController = MenuBarController(store: store)
    pillPanelController = PillPanelController(store: store.scope(state: \.pill, action: \.pill))
    store.send(.task)

    if ProcessInfo.processInfo.environment["MINIWHISPER_BENCHMARK_ACTIVATION"] == "1" {
      Task {
        try await Task.sleep(for: .seconds(2))
        for _ in 0..<3 {
          performanceLogger.notice("benchmark activation-triggered")
          store.send(.hotkeyListenerEvent(.gesture(.startRecording)))
          try await Task.sleep(for: .seconds(2))
          performanceLogger.notice("benchmark recording-release")
          store.send(.hotkeyListenerEvent(.gesture(.stopAndTranscribe)))
          try await Task.sleep(for: .seconds(3))
        }
        NSApp.terminate(nil)
      }
    }
  }
}
