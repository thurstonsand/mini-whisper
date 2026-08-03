// MARK: - GestureEvent

public enum GestureEvent: String, Equatable, Sendable {
  case startRecording
  case stopAndTranscribe
  case latchEngaged
  case cancel
}

// MARK: - HotkeyGestureMachine

public struct HotkeyGestureMachine: Equatable, Sendable {
  // MARK: Lifecycle

  public init(timing: Timing = Timing(), initiallyBlocked: Bool = false) {
    self.timing = timing
    phase = initiallyBlocked ? .blockedUntilRelease : .idle
  }

  // MARK: Public

  public struct Timing: Equatable, Sendable {
    // MARK: Lifecycle

    public init(
      doubleTapWindow: Duration = .milliseconds(300),
      accidentalInputWindow: Duration = .milliseconds(300),
    ) {
      self.doubleTapWindow = doubleTapWindow
      self.accidentalInputWindow = accidentalInputWindow
    }

    // MARK: Public

    public let doubleTapWindow: Duration
    public let accidentalInputWindow: Duration
  }

  public enum Phase: Equatable, Sendable {
    case idle
    case holding(startedAt: Duration)
    case latched
    case blockedUntilRelease
  }

  public private(set) var phase: Phase
  public let timing: Timing

  public mutating func receive(_ input: GestureInput) -> GestureEvent? {
    switch input {
    case .escape:
      return escape()
    case .monitoringInterrupted:
      return interrupt()
    case .neutral:
      if phase == .blockedUntilRelease {
        phase = .idle
      }
      return nil
    case let .activation(time):
      return activate(at: time)
    case let .release(time):
      return release(at: time)
    case let .conflict(time):
      return conflict(at: time)
    case let .mouseDown(time):
      return mouseDown(at: time)
    }
  }

  // MARK: Private

  private var previousReleaseAt: Duration?

  private mutating func activate(at time: Duration) -> GestureEvent? {
    switch phase {
    case .idle:
      phase = .holding(startedAt: time)
      return .startRecording
    case .latched:
      phase = .blockedUntilRelease
      previousReleaseAt = nil
      return .stopAndTranscribe
    case .holding,
         .blockedUntilRelease:
      return nil
    }
  }

  private mutating func release(at time: Duration) -> GestureEvent? {
    switch phase {
    case .holding:
      if let previousReleaseAt, time - previousReleaseAt < timing.doubleTapWindow {
        phase = .latched
        self.previousReleaseAt = nil
        return .latchEngaged
      }
      phase = .idle
      previousReleaseAt = time
      return .stopAndTranscribe
    case .blockedUntilRelease:
      phase = .idle
      return nil
    case .idle,
         .latched:
      return nil
    }
  }

  private mutating func conflict(at time: Duration) -> GestureEvent? {
    guard case let .holding(startedAt) = phase else {
      if phase == .idle {
        phase = .blockedUntilRelease
      }
      return nil
    }
    guard time - startedAt < timing.accidentalInputWindow else {
      return nil
    }

    phase = .blockedUntilRelease
    previousReleaseAt = nil
    return .cancel
  }

  private mutating func mouseDown(at time: Duration) -> GestureEvent? {
    guard case let .holding(startedAt) = phase, time - startedAt < timing.accidentalInputWindow
    else {
      return nil
    }

    phase = .blockedUntilRelease
    previousReleaseAt = nil
    return .cancel
  }

  private mutating func escape() -> GestureEvent? {
    switch phase {
    case .idle:
      phase = .blockedUntilRelease
      previousReleaseAt = nil
      return nil
    case .holding,
         .latched:
      phase = .blockedUntilRelease
      previousReleaseAt = nil
      return .cancel
    case .blockedUntilRelease:
      return nil
    }
  }

  private mutating func interrupt() -> GestureEvent? {
    let wasRecording =
      switch phase {
      case .holding,
           .latched:
        true
      case .idle,
           .blockedUntilRelease:
        false
      }

    phase = .blockedUntilRelease
    previousReleaseAt = nil
    return wasRecording ? .cancel : nil
  }
}
