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
  private let agentScene: AgentDriveabilityScene?
  private let store: StoreOf<AppFeature>

  private var menuBarController: MenuBarController!
  private var pillPanelController: PillPanelController!
  private var onboardingWindowController: OnboardingWindowController!
  private var agentSceneDriver: AgentDriveabilitySceneDriver?

  override init() {
    let agentScene: AgentDriveabilityScene? = AgentDriveabilityScene.current
    let initialState = agentScene?.initialState ?? AppFeature.State()
    self.agentScene = agentScene
    self.store = Store(initialState: initialState) { AppFeature() }
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard
      agentScene != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    else { return }

    logger.notice("App started; structured logging ready")
    menuBarController = MenuBarController(store: store, refreshesStateOnOpen: agentScene == nil)
    pillPanelController = PillPanelController(store: store.scope(state: \.pill, action: \.pill))
    onboardingWindowController = OnboardingWindowController(
      store: store.scope(state: \.onboarding, action: \.onboarding),
      observesApplicationActivation: agentScene == nil)

    if let agentScene {
      agentSceneDriver = AgentDriveabilitySceneDriver(
        store: store,
        refreshMenu: { [weak menuBarController] in menuBarController?.refreshAgentScene() })
      if let initialAction = agentScene.initialAction { store.send(initialAction) }
      if agentScene.presentsAbout { menuBarController.presentAbout() }
      return
    }

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
