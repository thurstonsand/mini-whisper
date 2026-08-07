import AppKit
import ComposableArchitecture
import OSLog

private let soundsLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "sounds")

// MARK: - SoundsClient

@DependencyClient struct SoundsClient {
  var availableNames: @Sendable () async -> [String] = { [] }
  var play: @Sendable (String) async -> Void
}

// MARK: DependencyKey

extension SoundsClient: DependencyKey {
  static let liveValue = Self(
    availableNames: { SystemSounds.availableNames() },
    play: { name in await SystemSounds.play(name) },
  )
  /// Silence is the right behaviour for tests that are not about sounds; the ones that are inject
  /// a recorder.
  static let testValue = Self(availableNames: { [] }, play: { _ in })
}

extension DependencyValues {
  var sounds: SoundsClient {
    get { self[SoundsClient.self] }
    set { self[SoundsClient.self] = newValue }
  }
}

// MARK: - SystemSounds

private enum SystemSounds {
  // MARK: Internal

  static let fallbackNames = ["Basso", "Funk", "Pop", "Tink"]

  static func availableNames() -> [String] {
    do {
      return try FileManager.default
        .contentsOfDirectory(
          at: URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true),
          includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles],
        )
        .filter { try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true }
        .map { $0.deletingPathExtension().lastPathComponent }
        .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    } catch {
      soundsLogger.error(
        "System sound inventory failed; using classic names: \(error.localizedDescription, privacy: .public)",
      )
      return fallbackNames
    }
  }

  @MainActor static func play(_ name: String) {
    currentSound?.stop()
    guard let sound = NSSound(named: NSSound.Name(name)) else {
      currentSound = nil
      soundsLogger.error("Built-in sound missing: \(name, privacy: .public)")
      return
    }
    currentSound = sound
    sound.play()
  }

  // MARK: Private

  @MainActor private static var currentSound: NSSound?
}
