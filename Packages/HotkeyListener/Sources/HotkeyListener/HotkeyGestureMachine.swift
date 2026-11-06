// MARK: - GestureEvent

public enum GestureEvent: String, Equatable, Sendable {
  case startRecording
  case stopAndTranscribe
  /// The press that ended the recording came from a submit binding: the dictation sends Return
  /// once it lands.
  case stopAndSubmit
  case latchEngaged
  case discardRecording
  case cancelAndArchive
  /// A press while cleanup is pending: the polishing dictation steps into the background, its
  /// cleanup still running, and the press goes on to start a recording exactly as it would have
  /// from idle.
  case detachAndRecord
  /// The press that detached a dictation turned out to be a lone tap: its recording is discarded,
  /// and the dictation it detached is delivered as heard.
  case skipCleanup
  /// The same lone tap from a submit binding: the recording is discarded, and the dictation it
  /// detached keeps its cleanup and sends Return once it lands.
  case submitDetached
  /// Return pressed once the capture was over, which only reaches the machine when the user is
  /// at the target of the dictation still owed: it sends Return once it lands.
  case submitDictation
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
  /// The press now in progress began while cleanup was pending, so a lone tap means skip.
  public private(set) var pressDetachedCleanup = false
  /// The latest press came from a submit binding. Whichever press ends a recording decides.
  public private(set) var pressSubmits = false

  /// A recording the user is still speaking into, which Return ends and submits. A tap that may
  /// yet be discarded is not one.
  public var isRecording: Bool {
    switch phase {
    case .holding,
         .secondPress,
         .latched:
      true
    case .idle,
         .provisional,
         .blockedUntilRelease,
         .cleanupPending:
      false
    }
  }

  /// No capture is running or may yet start: a Return now can only be about a dictation already
  /// spoken.
  public var isCaptureOver: Bool {
    switch phase {
    case .idle,
         .blockedUntilRelease,
         .cleanupPending:
      true
    case .holding,
         .provisional,
         .secondPress,
         .latched:
      false
    }
  }

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
    case .submitKey:
      submitKey()
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
    case .refused:
      refuse()
    case let .activation(time, submits):
      activate(at: time, submits: submits)
    case let .release(time):
      release(at: time)
    case let .conflict(time):
      foreignInput(at: time, blocksIdle: true)
    case let .mouseDown(time):
      foreignInput(at: time, blocksIdle: false)
    }
  }

  // MARK: Private

  private mutating func activate(at time: Duration, submits: Bool) -> GestureEvent? {
    switch phase {
    case .idle:
      phase = .holding(startedAt: time)
      pressDetachedCleanup = false
      pressSubmits = submits
      return .startRecording
    case let .provisional(releasedAt):
      guard time - releasedAt < timing.doubleTapWindow else {
        phase = .blockedUntilRelease
        return lonelyTap()
      }
      phase = .secondPress(startedAt: time)
      pressSubmits = submits
      return nil
    case .latched:
      phase = .blockedUntilRelease
      pressSubmits = submits
      return stop()
    case .cleanupPending:
      phase = .holding(startedAt: time)
      pressDetachedCleanup = true
      pressSubmits = submits
      return .detachAndRecord
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
        return stop()
      }
      phase = .provisional(releasedAt: time)
      return nil
    case let .secondPress(startedAt):
      guard time - startedAt < timing.tapMaximumDuration else {
        phase = .idle
        return stop()
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
    // The app judges whether Escape was meant for the polishing dictation, and reports an end to
    // the wait only if it was; one meant for something else leaves the key's meaning in place.
    case .cleanupPending:
      return .cancelAndArchive
    case .holding,
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

  /// A held activation key still owes its release; a latch has none to wait for. Once the capture
  /// is over, Return changes nothing about the key: cleanup can still be skipped.
  private mutating func submitKey() -> GestureEvent? {
    switch phase {
    case .holding,
         .secondPress:
      phase = .blockedUntilRelease
      return .stopAndSubmit
    case .latched:
      phase = .idle
      return .stopAndSubmit
    case .idle,
         .blockedUntilRelease,
         .cleanupPending:
      return .submitDictation
    case .provisional:
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
    return lonelyTap()
  }

  /// A tap that no second press followed. Only silence or a too-late press makes one; a foreign
  /// key or an Escape is a misfire, which leaves a detached dictation polishing.
  private mutating func lonelyTap() -> GestureEvent {
    defer { pressDetachedCleanup = false }
    guard pressDetachedCleanup else {
      return .discardRecording
    }
    return pressSubmits ? .submitDetached : .skipCleanup
  }

  private func stop() -> GestureEvent {
    pressSubmits ? .stopAndSubmit : .stopAndTranscribe
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

  /// The app would not start the recording this press asked for, so the rest of the press means
  /// nothing. One that would have detached a polishing dictation detached nothing, and the wait
  /// it interrupted resumes.
  private mutating func refuse() -> GestureEvent? {
    guard case .holding = phase else {
      return nil
    }
    phase = pressDetachedCleanup ? .cleanupPending : .blockedUntilRelease
    pressDetachedCleanup = false
    return nil
  }

  private mutating func neutral() -> GestureEvent? {
    if phase == .blockedUntilRelease {
      phase = .idle
    }
    return nil
  }
}
