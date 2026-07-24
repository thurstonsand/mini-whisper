public enum GestureEvent: String, Equatable, Sendable {
  case startRecording
  case stopAndTranscribe
  case latchEngaged
  case cancel
}

public struct HotkeyGestureMachine: Equatable, Sendable {
  public struct Timing: Equatable, Sendable {
    public let doubleTapWindow: Duration
    public let accidentalInputWindow: Duration

    public init(
      doubleTapWindow: Duration = .milliseconds(300),
      accidentalInputWindow: Duration = .milliseconds(300)
    ) {
      self.doubleTapWindow = doubleTapWindow
      self.accidentalInputWindow = accidentalInputWindow
    }
  }

  public enum Phase: Equatable, Sendable {
    case idle
    case holding(startedAt: Duration)
    case latched
    case blockedUntilRelease
  }

  public private(set) var phase: Phase
  public let timing: Timing

  private var previousReleaseAt: Duration?

  public init(timing: Timing = Timing(), initiallyBlocked: Bool = false) {
    self.timing = timing
    self.phase = initiallyBlocked ? .blockedUntilRelease : .idle
  }

  public mutating func receive(_ input: GestureInput) -> GestureEvent? {
    switch input {
    case .escape: return escape()
    case .monitoringInterrupted: return interrupt()
    case .neutral:
      if phase == .blockedUntilRelease { phase = .idle }
      return nil
    case .activation(let time): return activate(at: time)
    case .release(let time): return release(at: time)
    case .conflict(let time): return conflict(at: time)
    case .mouseDown(let time): return mouseDown(at: time)
    }
  }

  private mutating func activate(at time: Duration) -> GestureEvent? {
    switch phase {
    case .idle:
      phase = .holding(startedAt: time)
      return .startRecording
    case .latched:
      phase = .blockedUntilRelease
      previousReleaseAt = nil
      return .stopAndTranscribe
    case .holding, .blockedUntilRelease: return nil
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
    case .idle, .latched: return nil
    }
  }

  private mutating func conflict(at time: Duration) -> GestureEvent? {
    guard case .holding(let startedAt) = phase else {
      if phase == .idle { phase = .blockedUntilRelease }
      return nil
    }
    guard time - startedAt < timing.accidentalInputWindow else { return nil }

    phase = .blockedUntilRelease
    previousReleaseAt = nil
    return .cancel
  }

  private mutating func mouseDown(at time: Duration) -> GestureEvent? {
    guard case .holding(let startedAt) = phase, time - startedAt < timing.accidentalInputWindow
    else { return nil }

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
    case .holding, .latched:
      phase = .blockedUntilRelease
      previousReleaseAt = nil
      return .cancel
    case .blockedUntilRelease: return nil
    }
  }

  private mutating func interrupt() -> GestureEvent? {
    let wasRecording: Bool
    switch phase {
    case .holding, .latched: wasRecording = true
    case .idle, .blockedUntilRelease: wasRecording = false
    }

    phase = .blockedUntilRelease
    previousReleaseAt = nil
    return wasRecording ? .cancel : nil
  }
}
