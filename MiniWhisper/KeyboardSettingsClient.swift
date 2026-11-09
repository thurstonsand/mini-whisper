import ComposableArchitecture
import Foundation
import HotkeyListener

// MARK: - KeyboardShortcutSettings

struct KeyboardShortcutSettings: Equatable {
  // MARK: Lifecycle

  init(globeAction: Int?, symbolicHotkeys: [String: Any]) {
    self.globeAction = globeAction ?? 2
    if let dictation = symbolicHotkeys["164"] as? [String: Any],
       (dictation["enabled"] as? NSNumber)?.boolValue == true,
       let value = dictation["value"] as? [String: Any],
       value["type"] as? String == "modifier",
       let parameters = value["parameters"] as? [Int]
    {
      dictationModifier = parameters.first
    }
  }

  // MARK: Internal

  var globeAction: Int
  var dictationModifier: Int?

  func warning(for hotkey: Hotkey) -> String? {
    if hotkey.modifiers.contains(.function), globeAction != 0 {
      return "Set “Press 🌐 key to” to Do Nothing."
    }
    guard hotkey.keyCode == nil else {
      return nil
    }
    let conflicting: Set<ModifierKey> =
      switch dictationModifier {
      case 262_144:
        [.leftControl, .rightControl]
      case 1_048_592:
        [.rightCommand]
      case 1_048_584:
        [.leftCommand]
      case 1_048_576:
        [.leftCommand, .rightCommand]
      default:
        []
      }
    guard !hotkey.modifiers.isDisjoint(with: conflicting) else {
      return nil
    }
    return "Change the Dictation shortcut so a double-tap only starts MiniWhisper."
  }
}

// MARK: - KeyboardSettingsClient

@DependencyClient struct KeyboardSettingsClient {
  var snapshots: @Sendable () -> AsyncStream<KeyboardShortcutSettings> = {
    AsyncStream { $0.finish() }
  }
}

// MARK: DependencyKey

extension KeyboardSettingsClient: DependencyKey {
  static let liveValue = Self(snapshots: {
    AsyncStream { continuation in
      let observer = KeyboardSettingsObserver(continuation: continuation)
      continuation.onTermination = { _ in observer.stop() }
    }
  })
}

extension DependencyValues {
  var keyboardSettings: KeyboardSettingsClient {
    get { self[KeyboardSettingsClient.self] }
    set { self[KeyboardSettingsClient.self] = newValue }
  }
}

// MARK: - KeyboardSettingsObserver

private final class KeyboardSettingsObserver: NSObject, @unchecked Sendable {
  // MARK: Lifecycle

  init(continuation: AsyncStream<KeyboardShortcutSettings>.Continuation) {
    self.continuation = continuation
    super.init()
    hitoolbox.addObserver(self, forKeyPath: "AppleFnUsageType", options: [], context: nil)
    hotkeys.addObserver(self, forKeyPath: "AppleSymbolicHotKeys", options: [], context: nil)
    yield()
  }

  // MARK: Internal

  let hitoolbox = UserDefaults(suiteName: "com.apple.HIToolbox")!
  let hotkeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")!
  let continuation: AsyncStream<KeyboardShortcutSettings>.Continuation

  override func observeValue(
    forKeyPath _: String?, of _: Any?, change _: [NSKeyValueChangeKey: Any]?,
    context _: UnsafeMutableRawPointer?,
  ) {
    yield()
  }

  func stop() {
    hitoolbox.removeObserver(self, forKeyPath: "AppleFnUsageType")
    hotkeys.removeObserver(self, forKeyPath: "AppleSymbolicHotKeys")
  }

  // MARK: Private

  private func yield() {
    continuation.yield(KeyboardShortcutSettings(
      globeAction: (hitoolbox.object(forKey: "AppleFnUsageType") as? NSNumber)?.intValue,
      symbolicHotkeys: hotkeys.dictionary(forKey: "AppleSymbolicHotKeys") ?? [:],
    ))
  }
}
