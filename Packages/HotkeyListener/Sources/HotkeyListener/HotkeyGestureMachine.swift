// MARK: - GestureEvent

public enum GestureEvent: String, Equatable, Sendable {
  case startRecording
  case stopAndTranscribe
  case latchEngaged
  case discardRecording
  case cancelAndArchive
  /// One press, both meanings: the pending cleanup is abandoned and its transcript delivers as
  /// heard, and the press goes on to start a recording exactly as it would have from idle. A tap
  /// discards that recording on its own, which is what makes tap-to-skip need no case of its own.
  case skipCleanupAndRecord
}

// MARK: - HotkeyGestureMachine

public struct HotkeyGestureMachine: Equatable, Sendable {
  // MARK: Lifecycle

  public init(timing: Timing = .standard) {
    self.timing = timing
  }

  // MARK: Public

  public struct Timing: Equatable, Sendable {
    // MARK: Lifecycle

    public init(
      tapMaximumDuration: Duration = .milliseconds(200),
      doubleTapWindow: Duration = .milliseconds(300),
      accidentalInputWindow: Duration = .milliseconds(300),
    ) {
      self.tapMaximumDuration = tapMaximumDuration
      self.doubleTapWindow = doubleTapWindow
      self.accidentalInputWindow = accidentalInputWindow
    }

    // MARK: Public

    public static let standard = Timing()

    /// Measures one press from down to up; shorter presses are taps, while the boundary is a hold.
    public let tapMaximumDuration: Duration
    /// Measures first release to second press, matching the conventional double-tap timeout.
    public let doubleTapWindow: Duration
    /// Measures how long foreign input can still reveal an activation-chord misfire.
    public let accidentalInputWindow: Duration
  }

  public enum Phase: Equatable, Sendable {
    case idle
    case holding(startedAt: Duration)
    case provisional(releasedAt: Duration)
    case secondPress(startedAt: Duration)
    case latched
    case blockedUntilRelease
    /// A transcript is waiting on the cleanup endpoint. Delivery has not happened yet, so the
    /// activation key means something here that it means nowhere else.
    case cleanupPending
  }

  public private(set) var phase = Phase.idle
  public let timing: Timing

  /// Provisional is the only phase silence can resolve, so it is the only one that owes its owner
  /// a `deadlineElapsed` after `timing.doubleTapWindow`. The machine keeps no clock of its own.
  public var awaitsDeadline: Bool {
    if case .provisional = phase {
      true
    } else {
      false
    }
  }

  public mutating func receive(_ input: GestureInput) -> GestureEvent? {
    switch input {
    case .escape:
      escape()
    case .monitoringInterrupted:
      interrupt()
    case .deadlineElapsed:
      deadlineElapsed()
    case .neutral:
      neutral()
    case .cleanupStarted:
      beginCleanup()
    case .cleanupEnded:
      endCleanup()
    case let .activation(time):
      activate(at: time)
    case let .release(time):
      release(at: time)
    case let .conflict(time):
      foreignInput(at: time, blocksIdle: true)
    case let .mouseDown(time):
      foreignInput(at: time, blocksIdle: false)
    }
  }

  // MARK: Private

  private mutating func activate(at time: Duration) -> GestureEvent? {
    switch phase {
    case .idle:
      phase = .holding(startedAt: time)
      return .startRecording
    case let .provisional(releasedAt):
      guard time - releasedAt < timing.doubleTapWindow else {
        phase = .blockedUntilRelease
        return .discardRecording
      }
      phase = .secondPress(startedAt: time)
      return nil
    case .latched:
      phase = .blockedUntilRelease
      return .stopAndTranscribe
    case .cleanupPending:
      phase = .holding(startedAt: time)
      return .skipCleanupAndRecord
    case .holding,
         .secondPress,
         .blockedUntilRelease:
      return nil
    }
  }

  private mutating func release(at time: Duration) -> GestureEvent? {
    switch phase {
    case let .holding(startedAt):
      guard time - startedAt < timing.tapMaximumDuration else {
        phase = .idle
        return .stopAndTranscribe
      }
      phase = .provisional(releasedAt: time)
      return nil
    case let .secondPress(startedAt):
      guard time - startedAt < timing.tapMaximumDuration else {
        phase = .idle
        return .stopAndTranscribe
      }
      phase = .latched
      return .latchEngaged
    case .blockedUntilRelease:
      phase = .idle
      return nil
    case .cleanupPending,
         .idle,
         .provisional,
         .latched:
      return nil
    }
  }

  private mutating func foreignInput(
    at time: Duration, blocksIdle: Bool,
  ) -> GestureEvent? {
    switch phase {
    case let .holding(startedAt),
         let .secondPress(startedAt):
      guard time - startedAt < timing.accidentalInputWindow else {
        return nil
      }
      phase = .blockedUntilRelease
      return .discardRecording
    case .provisional:
      phase = .blockedUntilRelease
      return .discardRecording
    case .idle:
      if blocksIdle {
        phase = .blockedUntilRelease
      }
      return nil
    // Typing on while the endpoint thinks discards nothing: the recording is over, and the
    // transcript is already owed to whatever the user does next.
    case .cleanupPending,
         .latched,
         .blockedUntilRelease:
      return nil
    }
  }

  private mutating func escape() -> GestureEvent? {
    switch phase {
    case .cleanupPending,
         .holding,
         .secondPress,
         .latched:
      phase = .blockedUntilRelease
      return .cancelAndArchive
    case .provisional:
      phase = .blockedUntilRelease
      return .discardRecording
    case .idle:
      phase = .blockedUntilRelease
      return nil
    case .blockedUntilRelease:
      return nil
    }
  }

  private mutating func interrupt() -> GestureEvent? {
    let event: GestureEvent? =
      switch phase {
      case .holding,
           .secondPress,
           .latched:
        GestureEvent.cancelAndArchive
      case .provisional:
        GestureEvent.discardRecording
      // A tap that died has nothing to deliver; a cleanup that is already in flight still does,
      // and losing the tap is no reason to throw the transcript away.
      case .cleanupPending,
           .idle,
           .blockedUntilRelease:
        nil
      }
    phase = .blockedUntilRelease
    return event
  }

  private mutating func deadlineElapsed() -> GestureEvent? {
    guard case .provisional = phase else {
      return nil
    }
    phase = .idle
    return .discardRecording
  }

  /// Only an idle machine can start waiting on cleanup: a press that already began the next
  /// dictation has taken the key's meaning with it.
  private mutating func beginCleanup() -> GestureEvent? {
    if phase == .idle {
      phase = .cleanupPending
    }
    return nil
  }

  private mutating func endCleanup() -> GestureEvent? {
    if phase == .cleanupPending {
      phase = .idle
    }
    return nil
  }

  private mutating func neutral() -> GestureEvent? {
    if phase == .blockedUntilRelease {
      phase = .idle
    }
    return nil
  }
}
