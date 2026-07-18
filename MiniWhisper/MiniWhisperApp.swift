import ComposableArchitecture
import SwiftUI

@main struct MiniWhisperApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene { Settings { Text("Settings placeholder").frame(width: 300, height: 200) } }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  private let store = Store(initialState: AppFeature.State()) { AppFeature() }

  private var menuBarController: MenuBarController!

  func applicationDidFinishLaunching(_ notification: Notification) {
    menuBarController = MenuBarController(store: store)
    store.send(.task)
  }
}
