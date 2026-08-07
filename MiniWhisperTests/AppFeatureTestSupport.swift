import FieldContext
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
