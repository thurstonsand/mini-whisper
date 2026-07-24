import ComposableArchitecture
import OSLog
import SwiftUI

@main struct MiniWhisperApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene { Settings { EmptyView() } }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  private let logger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "lifecycle")
  private let store = Store(initialState: AppFeature.State()) { AppFeature() }

  private var menuBarController: MenuBarController!

  func applicationDidFinishLaunching(_ notification: Notification) {
    logger.notice("App started; structured logging ready")
    menuBarController = MenuBarController(store: store)
    store.send(.task)
  }
}
