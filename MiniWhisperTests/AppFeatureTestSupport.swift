import AppSettings
import ASREngine
import AudioCapture
import FieldContext
import Foundation
import History
import HotkeyListener
@testable import MiniWhisper

// MARK: - Test hotkeys

extension HotkeyBindingsSettings {
  mutating func set(_ hotkeys: [Hotkey], for command: HotkeyCommand) {
    self = HotkeyBindingsSettings(
      activate: command == .activate ? hotkeys : self.hotkeys(for: .activate),
      pasteLastTranscript: command == .pasteLastTranscript
        ? hotkeys : self.hotkeys(for: .pasteLastTranscript),
    )
  }
}

extension Hotkey {
  static let testRightOption = try! Hotkey(modifiers: [.rightOption])
  static let testPasteLastTranscript = try! Hotkey(
    keyCode: 9, modifiers: [.leftOption, .leftCommand],
  )

  /// A binding for each command that none of the others claims.
  static func testBinding(for command: HotkeyCommand) -> Hotkey {
    switch command {
    case .activate:
      .testRightOption
    case .pasteLastTranscript:
      .testPasteLastTranscript
    }
  }
}

// MARK: - SoundRecorder

actor SoundRecorder {
  private(set) var recorded: [String] = []

  func record(_ name: String) {
    recorded.append(name)
  }
}

// MARK: - StringRecorder

actor StringRecorder {
  private(set) var values: [String] = []

  func record(_ value: String) {
    values.append(value)
  }
}

// MARK: - TargetRecorder

actor TargetRecorder {
  private(set) var targets: [DeliveryTarget] = []

  func record(_ target: DeliveryTarget) {
    targets.append(target)
  }
}

// MARK: - PrewarmCounter

actor PrewarmCounter {
  private(set) var count = 0

  var isEmpty: Bool {
    count == 0
  }

  func record() {
    count += 1
  }
}

// MARK: - SynchronousCounter

/// Counts calls made from inside a dependency closure, which cannot await an actor.
final class SynchronousCounter: @unchecked Sendable {
  // MARK: Internal

  var value: Int {
    lock.withLock { count }
  }

  func increment() {
    lock.withLock { count += 1 }
  }

  // MARK: Private

  private let lock = NSLock()
  private var count = 0
}

// MARK: - AppHealth.healthy

extension AppHealth {
  static let healthy = AppHealth(
    hotkeyTap: .active, micStatus: .granted, accessibilityGranted: true, engineReadiness: .ready,
  )
}

extension DeliveryTarget {
  /// A GUI target in `app` with nothing but its identity: enough for History and the prompt,
  /// and for tests whose delivery is stubbed.
  static func inApp(_ app: TargetApp, processID: pid_t = 1) -> DeliveryTarget {
    DeliveryTarget(app: app, processID: processID, window: nil, element: nil, pane: nil)
  }
}
