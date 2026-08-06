import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - HotkeyRecordingChord

public struct HotkeyRecordingChord: Equatable, Sendable {
  // MARK: Lifecycle

  public init(keyCodes: Set<UInt16> = [], modifiers: Set<ModifierKey> = []) {
    self.keyCodes = keyCodes
    self.modifiers = modifiers
  }

  // MARK: Public

  public let keyCodes: Set<UInt16>
  public let modifiers: Set<ModifierKey>
}

// MARK: - HotkeyRecorderValidationError

public enum HotkeyRecorderValidationError: Error, Equatable, Sendable {
  case multipleKeys
  case invalid(HotkeyValidationError)

  // MARK: Public

  public var message: String {
    switch self {
    case .multipleKeys:
      "Use at most one non-modifier key."
    case .invalid(.empty):
      "Press at least one key."
    case .invalid(.reservedKeyCode):
      "Escape is reserved for cancelling."
    case .invalid(.modifierKeyCode):
      "Use modifier keys as modifiers, not as the primary key."
    case .invalid(.unsupportedKeyCode):
      "That key is not supported."
    }
  }
}

// MARK: - HotkeyRecorderEvent

public enum HotkeyRecorderEvent: Equatable, Sendable {
  case chordChanged(HotkeyRecordingChord)
  case validationFailed(HotkeyRecorderValidationError)
  case committed(Hotkey)
  case cancelled
}

// MARK: - HotkeyRecorderMachine

public struct HotkeyRecorderMachine: Equatable, Sendable {
  // MARK: Lifecycle

  public init() {}

  // MARK: Public

  public mutating func receive(_ transition: KeyTransition) -> HotkeyRecorderEvent? {
    guard !transition.isRepeat else {
      return nil
    }
    if transition.key == .keyCode(PhysicalKey.escapeKeyCode), transition.phase == .down {
      return .cancelled
    }
    if transition.phase == .down {
      switch transition.key {
      case let .keyCode(keyCode):
        capturedKeyCodes.insert(keyCode)
      case let .modifier(modifier):
        capturedModifiers.insert(modifier)
      }
      return .chordChanged(chord)
    }
    guard transition.pressedAfter.isEmpty, !capturedKeyCodes.isEmpty || !capturedModifiers.isEmpty
    else {
      return nil
    }

    defer {
      capturedKeyCodes.removeAll()
      capturedModifiers.removeAll()
    }
    guard capturedKeyCodes.count <= 1 else {
      return .validationFailed(.multipleKeys)
    }
    do {
      return try .committed(
        Hotkey(keyCode: capturedKeyCodes.first, modifiers: capturedModifiers),
      )
    } catch let error as HotkeyValidationError {
      return .validationFailed(.invalid(error))
    } catch {
      preconditionFailure("Hotkey validation raised an unknown error: \(error)")
    }
  }

  // MARK: Private

  private var capturedKeyCodes: Set<UInt16> = []
  private var capturedModifiers: Set<ModifierKey> = []

  private var chord: HotkeyRecordingChord {
    HotkeyRecordingChord(keyCodes: capturedKeyCodes, modifiers: capturedModifiers)
  }
}

// MARK: - HotkeyRecorder

public enum HotkeyRecorder {
  public static func events() async throws -> AsyncStream<HotkeyRecorderEvent> {
    guard AXIsProcessTrusted() else {
      throw HotkeyRecorderError.accessibilityPermissionMissing
    }
    let (stream, continuation) = AsyncStream.makeStream(of: HotkeyRecorderEvent.self)
    let session = HotkeyRecorderSession(continuation: continuation)
    continuation.onTermination = { @Sendable _ in session.stop() }
    do {
      try await session.start()
      return stream
    } catch {
      continuation.finish()
      throw error
    }
  }
}

// MARK: - HotkeyRecorderError

public enum HotkeyRecorderError: Error, Equatable, Sendable {
  case accessibilityPermissionMissing
  case eventTapCreationFailed
}

// MARK: - HotkeyRecorderSession

private final class HotkeyRecorderSession: @unchecked Sendable {
  // MARK: Lifecycle

  init(continuation: AsyncStream<HotkeyRecorderEvent>.Continuation) {
    self.continuation = continuation
  }

  // MARK: Internal

  func start() async throws {
    try await withCheckedThrowingContinuation { startup in
      let thread = Thread { [self] in run(startup: startup) }
      thread.name = "MiniWhisper Hotkey Recorder"
      thread.qualityOfService = .userInteractive
      thread.start()
    }
  }

  func stop() {
    let runLoop = lock.withLock { self.runLoop }
    if let runLoop {
      CFRunLoopStop(runLoop)
    } else {
      finishStream()
    }
  }

  // MARK: Private

  private let lock = NSLock()
  private var continuation: AsyncStream<HotkeyRecorderEvent>.Continuation?
  private var runLoop: CFRunLoop?
  private var pressedKeys: Set<PhysicalKey> = []
  private var machine = HotkeyRecorderMachine()

  private func run(startup: CheckedContinuation<Void, any Error>) {
    let mask = [CGEventType.flagsChanged, .keyDown, .keyUp].reduce(CGEventMask(0)) {
      $0 | (CGEventMask(1) << $1.rawValue)
    }
    guard let tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
      eventsOfInterest: mask,
      callback: { _, type, event, userInfo in
        guard let userInfo else {
          return Unmanaged.passUnretained(event)
        }
        return Unmanaged<HotkeyRecorderSession>.fromOpaque(userInfo)
          .takeUnretainedValue()
          .receive(type: type, event: event)
      }, userInfo: Unmanaged.passUnretained(self).toOpaque(),
    ) else {
      startup.resume(throwing: HotkeyRecorderError.eventTapCreationFailed)
      return
    }
    CFMachPortSetInvalidationCallBack(tap) { _, userInfo in
      guard let userInfo else {
        return
      }
      Unmanaged<HotkeyRecorderSession>.fromOpaque(userInfo).takeUnretainedValue().stop()
    }
    let runLoop = CFRunLoopGetCurrent()
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    lock.withLock { self.runLoop = runLoop }
    CFRunLoopAddSource(runLoop, source, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    startup.resume()
    CFRunLoopRun()
    CGEvent.tapEnable(tap: tap, enable: false)
    CFRunLoopRemoveSource(runLoop, source, .commonModes)
    lock.withLock { self.runLoop = nil }
    finishStream()
  }

  private func receive(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      stop()
      return Unmanaged.passUnretained(event)
    }
    guard let transition = normalize(type: type, event: event) else {
      return Unmanaged.passUnretained(event)
    }
    if let recorderEvent = machine.receive(transition) {
      let continuation = lock.withLock { self.continuation }
      continuation?.yield(recorderEvent)
      switch recorderEvent {
      case .committed,
           .cancelled:
        stop()
      case .chordChanged,
           .validationFailed:
        break
      }
    }
    // Recording owns keyboard input. Besides preventing edits in the frontmost field, this makes
    // a binding such as Right Option incapable of reaching the activation listener.
    return nil
  }

  private func normalize(type: CGEventType, event: CGEvent) -> KeyTransition? {
    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let key: PhysicalKey
    let phase: KeyPhase
    if type == .flagsChanged,
       let modifier = ModifierKey.allCases.first(where: { $0.keyCode == keyCode })
    {
      key = .modifier(modifier)
      if modifier.isDown(in: event.flags) {
        pressedKeys.insert(key)
        phase = .down
      } else {
        pressedKeys.remove(key)
        phase = .up
      }
    } else if type == .keyDown {
      key = .keyCode(keyCode)
      pressedKeys.insert(key)
      phase = .down
    } else if type == .keyUp {
      key = .keyCode(keyCode)
      pressedKeys.remove(key)
      phase = .up
    } else {
      return nil
    }
    return KeyTransition(
      key: key, phase: phase,
      isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
      pressedAfter: pressedKeys, time: .nanoseconds(Int64(clamping: event.timestamp)),
    )
  }

  private func finishStream() {
    let continuation = lock.withLock {
      defer { self.continuation = nil }
      return self.continuation
    }
    continuation?.finish()
  }
}
