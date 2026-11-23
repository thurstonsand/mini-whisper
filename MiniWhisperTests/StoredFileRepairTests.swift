import AppSettings
import AudioCapture
import ComposableArchitecture
import Foundation
import History
@testable import MiniWhisper
import Testing

@MainActor struct StoredFileRepairTests {
  // MARK: Internal

  @Test func `an unreadable settings file is flagged at launch and reset to the defaults`(
  ) async throws {
    let (store, settingsURL) = try launchWithMalformedSettings()

    await store.send(.task)
    #expect(store.state.health.degradations.contains(.settingsFileUnreadable))
    #expect(try Data(contentsOf: settingsURL) == malformed)

    await store.send(.settingsWindow(.settingsPane(.delegate(.resetFile(.settings)))))
    await store.receive(.storedFileReadable(.settings))

    #expect(!store.state.health.degradations.contains(.settingsFileUnreadable))
    #expect(try SettingsCoding.decode(Data(contentsOf: settingsURL)) == .defaults)
  }

  /// Any setting saved over the broken file makes it readable, and the warning goes with it.
  @Test func `an ordinary settings change clears the unreadable warning`() async throws {
    let (store, settingsURL) = try launchWithMalformedSettings()

    await store.send(.task)
    #expect(store.state.health.degradations.contains(.settingsFileUnreadable))

    await store.send(.settingsWindow(.settingsPane(.soundThemeSelected(.hum))))
    await store.receive(.storedFileReadable(.settings), timeout: .seconds(5))

    #expect(!store.state.health.degradations.contains(.settingsFileUnreadable))
    #expect(try SettingsCoding.decode(Data(contentsOf: settingsURL)).soundTheme == .hum)
  }

  // MARK: Private

  private let malformed = Data("{ \"soundTheme\": ".utf8)

  private func launchWithMalformedSettings() throws -> (TestStoreOf<AppFeature>, URL) {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "settings-\(UUID().uuidString)", directoryHint: .isDirectory,
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let settingsURL = root.appending(path: "settings.json")
    try malformed.write(to: settingsURL)

    let state = withDependencies {
      $0.defaultFileStorage = .fileSystem
    } operation: {
      AppFeature.State(
        history: Shared(value: HistoryLog()),
        settings: Shared(
          wrappedValue: .defaults,
          .fileStorage(settingsURL, decode: SettingsCoding.decode, encode: SettingsCoding.encode),
        ),
      )
    }
    let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
      $0.defaultFileStorage = .fileSystem
      $0.audioCapture.prepare = { _ in }
      $0.asrEngine.prepareInstalled = { _ in AsyncStream { $0.finish() } }
      $0.microphonePermission.status = { .granted }
      $0.accessibilityPermission.hasPermission = { false }
      $0.screenContext.hasScreenRecording = { false }
      $0.onboardingCompletion.isCompleted = { true }
      $0.modelDownloadConsent.isConsented = { true }
      $0.date.now = Date(timeIntervalSince1970: 1000)
      $0.sounds.play = { _ in }
      $0.continuousClock = ImmediateClock()
    }
    store.exhaustivity = .off(showSkippedAssertions: false)
    return (store, settingsURL)
  }
}
