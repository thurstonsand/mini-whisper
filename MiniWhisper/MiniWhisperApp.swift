import ComposableArchitecture
import HotkeyListener
import OSLog
import SwiftUI

// MARK: - MiniWhisperApp

@main struct MiniWhisperApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    Settings { EmptyView() }
  }
}

// MARK: - AppDelegate

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  // MARK: Lifecycle

  override init() {
    let agentScene: AgentDriveabilityScene? = AgentDriveabilityScene.current
    let initialState = agentScene?.initialState ?? AppFeature.State()
    self.agentScene = agentScene
    store = Store(initialState: initialState) { AppFeature() } withDependencies: {
      agentScene?.configure(&$0)
    }
    super.init()
  }

  // MARK: Internal

  func applicationDidFinishLaunching(_: Notification) {
    guard isDrivingTheRealApp else {
      return
    }

    switch ProcessInfo.processInfo.environment["MINIWHISPER_AGENT_APPEARANCE"] {
    case "dark":
      NSApp.appearance = NSAppearance(named: .darkAqua)
    case "light":
      NSApp.appearance = NSAppearance(named: .aqua)
    default:
      break
    }

    logger.notice("App started; structured logging ready")
    menuBarController = MenuBarController(store: store, refreshesStateOnOpen: agentScene == nil)
    pillPanelController = PillPanelController(store: store.scope(state: \.pill, action: \.pill))
    onboardingWindowController = OnboardingWindowController(
      store: store.scope(state: \.onboarding, action: \.onboarding),
      observesApplicationActivation: agentScene == nil,
    )

    if let agentScene {
      agentSceneDriver = AgentDriveabilitySceneDriver(store: store)
      if let initialAction = agentScene.initialAction {
        store.send(initialAction)
      }
      switch agentScene.presentedWindow {
      case let .settings(destination, initialFocus):
        menuBarController.presentSettings(destination: destination, initialFocus: initialFocus)
      case .about:
        menuBarController.presentAbout()
      case nil:
        break
      }
      return
    }

    store.send(.task)

    if ProcessInfo.processInfo.environment["MINIWHISPER_BENCHMARK_ACTIVATION"] == "1" {
      Task {
        try await Task.sleep(for: .seconds(2))
        for _ in 0 ..< 3 {
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

  /// A grant made in System Settings is invisible to a running app, so returning to MiniWhisper is
  /// the moment to look again.
  func applicationDidBecomeActive(_: Notification) {
    guard isDrivingTheRealApp, agentScene == nil else {
      return
    }
    store.send(.applicationBecameActive)
  }

  // MARK: Private

  private let logger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "lifecycle")
  private let performanceLogger = Logger(
    subsystem: "com.thurstonsand.MiniWhisper", category: "performance",
  )
  private let agentScene: AgentDriveabilityScene?
  private let store: StoreOf<AppFeature>

  private var menuBarController: MenuBarController!
  private var pillPanelController: PillPanelController!
  private var onboardingWindowController: OnboardingWindowController!
  private var agentSceneDriver: AgentDriveabilitySceneDriver?

  private var isDrivingTheRealApp: Bool {
    agentScene != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
  }
}
