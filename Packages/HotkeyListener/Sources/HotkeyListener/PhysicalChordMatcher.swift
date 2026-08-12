// MARK: - PhysicalKey

public enum PhysicalKey: Hashable, Sendable {
  case keyCode(UInt16)
  case modifier(ModifierKey)

  // MARK: Public

  public static let escapeKeyCode: UInt16 = 53
}

// MARK: - KeyPhase

public enum KeyPhase: Equatable, Sendable {
  case down
  case up
}

// MARK: - KeyTransition

public struct KeyTransition: Equatable, Sendable {
  // MARK: Lifecycle

  public init(
    key: PhysicalKey, phase: KeyPhase, isRepeat: Bool = false, pressedAfter: Set<PhysicalKey>,
    time: Duration,
  ) {
    self.key = key
    self.phase = phase
    self.isRepeat = isRepeat
    self.pressedAfter = pressedAfter
    self.time = time
  }

  // MARK: Public

  public let key: PhysicalKey
  public let phase: KeyPhase
  public let isRepeat: Bool
  public let pressedAfter: Set<PhysicalKey>
  public let time: Duration
}

// MARK: - GestureInput

public enum GestureInput: Equatable, Sendable {
  case activation(at: Duration)
  case release(at: Duration)
  case conflict(at: Duration)
  case mouseDown(at: Duration)
  case deadlineElapsed
  case escape
  case monitoringInterrupted
  case neutral

  // MARK: Public

  public var isActivation: Bool {
    if case .activation = self {
      true
    } else {
      false
    }
  }

  public var isRelease: Bool {
    if case .release = self {
      true
    } else {
      false
    }
  }
}

// MARK: - EventDisposition

public enum EventDisposition: Equatable, Sendable {
  case passThrough
  case suppress
}

// MARK: - ChordMatch

public struct ChordMatch: Equatable, Sendable {
  // MARK: Lifecycle

  public init(input: GestureInput?, disposition: EventDisposition) {
    self.input = input
    self.disposition = disposition
  }

  // MARK: Public

  public let input: GestureInput?
  public let disposition: EventDisposition
}

// MARK: - PhysicalChordMatcher

public struct PhysicalChordMatcher: Equatable, Sendable {
  // MARK: Lifecycle

  public init(hotkey: Hotkey) {
    self.hotkey = hotkey
  }

  // MARK: Public

  public let hotkey: Hotkey

  public mutating func receive(_ transition: KeyTransition) -> ChordMatch {
    let disposition = disposition(for: transition)

    if transition.key == .keyCode(PhysicalKey.escapeKeyCode), transition.phase == .down {
      return ChordMatch(input: .escape, disposition: .passThrough)
    }

    if hotkey.keyCode == nil {
      return ChordMatch(input: modifierOnlyInput(for: transition), disposition: .passThrough)
    }

    return ChordMatch(input: keyedInput(for: transition), disposition: disposition)
  }

  /// Abandons the gesture but not the suppression: a key whose down was swallowed still owes the
  /// app a swallowed up, or the frontmost field sees a key-up it never saw pressed.
  public mutating func interrupt() {
    isActive = false
  }

  // MARK: Private

  private var isActive = false
  private var suppressedKeyIsDown = false

  private mutating func disposition(for transition: KeyTransition) -> EventDisposition {
    guard let keyCode = hotkey.keyCode, transition.key == .keyCode(keyCode) else {
      return .passThrough
    }

    if transition.phase == .up, suppressedKeyIsDown {
      suppressedKeyIsDown = false
      return .suppress
    }

    if transition.phase == .down, transitionMatchesKeyedHotkey(transition) {
      suppressedKeyIsDown = true
      return .suppress
    }

    return suppressedKeyIsDown && transition.isRepeat ? .suppress : .passThrough
  }

  private mutating func modifierOnlyInput(for transition: KeyTransition) -> GestureInput? {
    let required = Set(hotkey.modifiers.map(PhysicalKey.modifier))
    let exactMatch = transition.pressedAfter == required
    let requiredStillPressed = required.isSubset(of: transition.pressedAfter)

    if isActive {
      if !requiredStillPressed {
        isActive = false
        return .release(at: transition.time)
      }
      return exactMatch ? nil : .conflict(at: transition.time)
    }

    if exactMatch, transition.phase == .down {
      isActive = true
      return .activation(at: transition.time)
    }
    if transition.pressedAfter.isEmpty {
      return .neutral
    }
    if transition.pressedAfter.isSubset(of: required) {
      return nil
    }
    return transition.phase == .down ? .conflict(at: transition.time) : nil
  }

  private mutating func keyedInput(for transition: KeyTransition) -> GestureInput? {
    guard let keyCode = hotkey.keyCode else {
      return nil
    }
    let primaryKey = PhysicalKey.keyCode(keyCode)

    if isActive {
      if transition.key == primaryKey, transition.phase == .up {
        isActive = false
        return .release(at: transition.time)
      }
      return transition.phase == .down && transition.key != primaryKey
        ? .conflict(at: transition.time) : nil
    }

    if transitionMatchesKeyedHotkey(transition) {
      isActive = true
      return .activation(at: transition.time)
    }
    if transition.pressedAfter.isEmpty {
      return .neutral
    }

    let allowed = Set(hotkey.modifiers.map(PhysicalKey.modifier)).union([primaryKey])
    if transition.pressedAfter.isSubset(of: allowed) {
      return nil
    }
    return transition.phase == .down ? .conflict(at: transition.time) : nil
  }

  private func transitionMatchesKeyedHotkey(_ transition: KeyTransition) -> Bool {
    guard let keyCode = hotkey.keyCode else {
      return false
    }
    let required = Set(hotkey.modifiers.map(PhysicalKey.modifier)).union([.keyCode(keyCode)])
    return transition.key == .keyCode(keyCode) && transition.phase == .down
      && transition.pressedAfter == required
  }
}
