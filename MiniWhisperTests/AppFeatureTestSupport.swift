import ASREngine
import AudioCapture
import FieldContext
import Foundation
@testable import MiniWhisper

// MARK: - SoundRecorder

actor SoundRecorder {
  private(set) var recorded: [String] = []

  func record(_ name: String) {
    recorded.append(name)
  }
}

// MARK: - CaptureSequence

/// Hands back a scripted sequence of captures so a test can tell the release-time warm-up read
/// apart from the authoritative read taken at delivery.
actor CaptureSequence {
  // MARK: Lifecycle

  init(captures: [ContextCapture]) {
    remaining = captures
  }

  // MARK: Internal

  private(set) var taken = 0

  func next() -> ContextCapture {
    taken += 1
    return remaining.isEmpty ? .unavailable(.noFocusedElement) : remaining.removeFirst()
  }

  // MARK: Private

  private var remaining: [ContextCapture]
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
