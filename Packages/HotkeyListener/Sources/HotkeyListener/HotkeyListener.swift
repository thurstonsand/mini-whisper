import CoreGraphics
import Foundation
import OSLog

private let performanceLogger = Logger(
  subsystem: "com.thurstonsand.MiniWhisper", category: "performance")

public enum TapDisableReason: String, Equatable, Sendable {
  case timeout
  case userInput
  case invalidated
}

public enum HotkeyListenerEvent: Equatable, Sendable {
  case inputMonitoringPermissionMissing
  case monitoringStarted
  case gesture(GestureEvent)
  case monitoringInterrupted(TapDisableReason)
}

public enum HotkeyListenerError: Error, Equatable, Sendable { case eventTapCreationFailed }

public enum HotkeyListener {
  public static func events(hotkey: Hotkey) async throws -> AsyncStream<HotkeyListenerEvent> {
    let (stream, continuation) = AsyncStream.makeStream(of: HotkeyListenerEvent.self)
    guard CGPreflightListenEventAccess() else {
      _ = CGRequestListenEventAccess()
      continuation.yield(.inputMonitoringPermissionMissing)
      continuation.finish()
      return stream
    }

    let session = EventTapSession(hotkey: hotkey, continuation: continuation)
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

private final class EventTapSession: @unchecked Sendable {
  private static let capsLockKeyCode: UInt16 = 57

  private let lock = NSLock()
  private let hotkey: Hotkey

  private var continuation: AsyncStream<HotkeyListenerEvent>.Continuation?
  private var runLoop: CFRunLoop?
  private var eventTap: CFMachPort?
  private var stopWasRequested = false
  private var pressedKeys: Set<PhysicalKey> = []
  private var matcher: PhysicalChordMatcher
  private var gestureMachine = HotkeyGestureMachine()

  init(hotkey: Hotkey, continuation: AsyncStream<HotkeyListenerEvent>.Continuation) {
    self.hotkey = hotkey
    self.continuation = continuation
    self.matcher = PhysicalChordMatcher(hotkey: hotkey)
  }

  func start() async throws {
    try await withCheckedThrowingContinuation { startup in
      let thread = Thread { [self] in run(startup: startup) }
      thread.name = "MiniWhisper Hotkey Listener"
      thread.qualityOfService = .userInteractive
      thread.start()
    }
  }

  func stop() {
    let runLoop = lock.withLock {
      stopWasRequested = true
      return self.runLoop
    }
    if let runLoop { CFRunLoopStop(runLoop) } else { finishStream() }
  }

  private func run(startup: CheckedContinuation<Void, any Error>) {
    pressedKeys = currentlyPressedKeys()
    gestureMachine = HotkeyGestureMachine(initiallyBlocked: !pressedKeys.isEmpty)

    let mask = [
      CGEventType.flagsChanged, .keyDown, .keyUp, .leftMouseDown, .rightMouseDown, .otherMouseDown,
    ].reduce(CGEventMask(0)) { mask, type in mask | (CGEventMask(1) << type.rawValue) }
    let options: CGEventTapOptions = hotkey.keyCode == nil ? .listenOnly : .defaultTap

    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: options,
        eventsOfInterest: mask,
        callback: { _, type, event, userInfo in
          guard let userInfo else { return Unmanaged.passUnretained(event) }
          let session = Unmanaged<EventTapSession>.fromOpaque(userInfo).takeUnretainedValue()
          return session.receive(type: type, event: event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
    else {
      startup.resume(throwing: HotkeyListenerError.eventTapCreationFailed)
      return
    }

    CFMachPortSetInvalidationCallBack(eventTap) { _, userInfo in
      guard let userInfo else { return }
      let session = Unmanaged<EventTapSession>.fromOpaque(userInfo).takeUnretainedValue()
      session.stopAfterInvalidation()
    }

    let runLoop = CFRunLoopGetCurrent()
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    lock.withLock {
      self.eventTap = eventTap
      self.runLoop = runLoop
    }
    CFRunLoopAddSource(runLoop, source, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)
    yield(.monitoringStarted)
    startup.resume()
    CFRunLoopRun()

    let expectedStop = lock.withLock { stopWasRequested }
    if !expectedStop { interrupt(reason: .invalidated, reenable: false) }
    CGEvent.tapEnable(tap: eventTap, enable: false)
    CFRunLoopRemoveSource(runLoop, source, .commonModes)
    lock.withLock {
      self.eventTap = nil
      self.runLoop = nil
    }
    finishStream()
  }

  private func receive(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      interrupt(reason: type == .tapDisabledByTimeout ? .timeout : .userInput, reenable: true)
      return Unmanaged.passUnretained(event)
    }

    let time = Duration.nanoseconds(Int64(clamping: event.timestamp))
    if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown {
      emit(gestureMachine.receive(.mouseDown(at: time)))
      return Unmanaged.passUnretained(event)
    }

    guard let transition = normalize(type: type, event: event, time: time) else {
      return Unmanaged.passUnretained(event)
    }
    let match = matcher.receive(transition)
    if let input = match.input { emit(gestureMachine.receive(input)) }
    return match.disposition == .suppress ? nil : Unmanaged.passUnretained(event)
  }

  private func normalize(type: CGEventType, event: CGEvent, time: Duration) -> KeyTransition? {
    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    let key: PhysicalKey
    let phase: KeyPhase

    if type == .flagsChanged,
      let modifier = ModifierKey.allCases.first(where: { $0.keyCode == keyCode })
    {
      key = .modifier(modifier)
      if isModifierDown(modifier, event: event) {
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
      key: key, phase: phase, isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
      pressedAfter: pressedKeys, time: time)
  }

  private func isModifierDown(_ modifier: ModifierKey, event: CGEvent) -> Bool {
    // A head-insert callback runs before session HID state updates, so event flags are authoritative.
    modifier.isDown(in: event.flags)
  }

  private func interrupt(reason: TapDisableReason, reenable: Bool) {
    emit(gestureMachine.receive(.monitoringInterrupted))
    pressedKeys = currentlyPressedKeys()
    matcher.interrupt()
    if pressedKeys.isEmpty { _ = gestureMachine.receive(.neutral) }
    yield(.monitoringInterrupted(reason))
    if reenable, let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
  }

  private func stopAfterInvalidation() {
    let runLoop = lock.withLock { self.runLoop }
    if let runLoop { CFRunLoopStop(runLoop) }
  }

  private func currentlyPressedKeys() -> Set<PhysicalKey> {
    Set(
      (UInt16(0)...UInt16(127)).compactMap { keyCode in
        // Caps Lock reports its toggle state rather than whether the physical key is held.
        guard keyCode != Self.capsLockKeyCode,
          CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(keyCode))
        else { return nil }
        if let modifier = ModifierKey.allCases.first(where: { $0.keyCode == keyCode }) {
          return .modifier(modifier)
        }
        return .keyCode(keyCode)
      })
  }

  private func emit(_ event: GestureEvent?) {
    guard let event else { return }
    switch event {
    case .startRecording: performanceLogger.notice("benchmark hotkey-press")
    case .stopAndTranscribe: performanceLogger.notice("benchmark recording-release")
    case .latchEngaged, .cancel: break
    }
    yield(.gesture(event))
  }

  private func yield(_ event: HotkeyListenerEvent) {
    let continuation = lock.withLock { self.continuation }
    continuation?.yield(event)
  }

  private func finishStream() {
    let continuation = lock.withLock {
      defer { self.continuation = nil }
      return self.continuation
    }
    continuation?.finish()
  }
}
