import ApplicationServices
import CoreGraphics
import Foundation
import OSLog

private let performanceLogger = Logger(
  subsystem: "com.thurstonsand.MiniWhisper", category: "performance",
)

// MARK: - TapDisableReason

public enum TapDisableReason: String, Equatable, Sendable {
  case timeout
  case userInput
  case invalidated
}

// MARK: - HotkeyListenerEvent

public enum HotkeyListenerEvent: Equatable, Sendable {
  case accessibilityPermissionMissing
  case monitoringStarted
  case gestureInput(GestureInput)
  case gesture(GestureEvent)
  case monitoringInterrupted(TapDisableReason)
}

// MARK: - HotkeyListenerError

public enum HotkeyListenerError: Error, Equatable, Sendable { case eventTapCreationFailed }

// MARK: - HotkeyListener

public enum HotkeyListener {
  /// Starts listening without raising a permission dialog. A missing grant is reported as
  /// `.accessibilityPermissionMissing` so the caller can send the user to System Settings.
  public static func events(hotkeys: [Hotkey]) async throws -> AsyncStream<HotkeyListenerEvent> {
    let (stream, continuation) = AsyncStream.makeStream(of: HotkeyListenerEvent.self)
    // The last-mile guard: an Accessibility grant is what lets the session tap actually receive
    // keyboard events, and `AXIsProcessTrusted` answers live rather than caching a launch-time
    // value. Without it the tap creates and then hears nothing, which is worse than not starting.
    guard AXIsProcessTrusted() else {
      continuation.yield(.accessibilityPermissionMissing)
      continuation.finish()
      return stream
    }

    let session = EventTapSession(hotkeys: hotkeys, continuation: continuation)
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

// MARK: - EventTapSession

private final class EventTapSession: @unchecked Sendable {
  // MARK: Lifecycle

  init(hotkeys: [Hotkey], continuation: AsyncStream<HotkeyListenerEvent>.Continuation) {
    self.continuation = continuation
    matcher = MultipleChordMatcher(hotkeys: hotkeys)
  }

  // MARK: Internal

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
    if let runLoop {
      CFRunLoopStop(runLoop)
    } else {
      finishStream()
    }
  }

  // MARK: Private

  private let lock = NSLock()

  private var continuation: AsyncStream<HotkeyListenerEvent>.Continuation?
  private var runLoop: CFRunLoop?
  private var eventTap: CFMachPort?
  private var stopWasRequested = false
  private var pressedKeys: Set<PhysicalKey> = []
  private var matcher: MultipleChordMatcher

  private func run(startup: CheckedContinuation<Void, any Error>) {
    let mask = [
      CGEventType.flagsChanged, .keyDown, .keyUp, .leftMouseDown, .rightMouseDown, .otherMouseDown,
    ].reduce(CGEventMask(0)) { mask, type in mask | (CGEventMask(1) << type.rawValue) }
    // The tap option decides which permission macOS checks: `.listenOnly` is gated on Input
    // Monitoring, `.defaultTap` on Accessibility. macOS 26 refuses to prompt for Input Monitoring
    // at all, and MiniWhisper already requires Accessibility for the paste and the field read, so
    // every binding takes the modifying tap. Modification stays permitted, not obligatory: the
    // matcher suppresses a keyed hotkey's trigger and passes modifier-only bindings through.
    let options: CGEventTapOptions = .defaultTap

    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: options,
        eventsOfInterest: mask,
        callback: { _, type, event, userInfo in
          guard let userInfo else {
            return Unmanaged.passUnretained(event)
          }
          let session = Unmanaged<EventTapSession>.fromOpaque(userInfo).takeUnretainedValue()
          return session.receive(type: type, event: event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque(),
      )
    else {
      startup.resume(throwing: HotkeyListenerError.eventTapCreationFailed)
      return
    }

    CFMachPortSetInvalidationCallBack(eventTap) { _, userInfo in
      guard let userInfo else {
        return
      }
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
    if !expectedStop {
      interrupt(reason: .invalidated, reenable: false)
    }
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
      emit(.mouseDown(at: time))
      return Unmanaged.passUnretained(event)
    }

    guard let transition = normalize(type: type, event: event, time: time) else {
      return Unmanaged.passUnretained(event)
    }
    let match = matcher.receive(transition)
    if let input = match.input {
      emit(input)
    }
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
      pressedAfter: pressedKeys, time: time,
    )
  }

  private func isModifierDown(_ modifier: ModifierKey, event: CGEvent) -> Bool {
    // A head-insert callback runs before session HID state updates, so event flags are
    // authoritative.
    modifier.isDown(in: event.flags)
  }

  private func interrupt(reason: TapDisableReason, reenable: Bool) {
    emit(.monitoringInterrupted)
    pressedKeys.removeAll()
    matcher.interrupt()
    emit(.neutral)
    yield(.monitoringInterrupted(reason))
    if reenable, let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: true)
    }
  }

  private func stopAfterInvalidation() {
    let runLoop = lock.withLock { self.runLoop }
    if let runLoop {
      CFRunLoopStop(runLoop)
    }
  }

  private func emit(_ input: GestureInput) {
    if input.isActivation {
      performanceLogger.notice("benchmark hotkey-press")
    }
    yield(.gestureInput(input))
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
