import CoreGraphics
import Foundation
import HotkeyListener

private let inputHoldCallback: CGEventTapCallBack = { _, type, event, userInfo in
  guard let userInfo else {
    return Unmanaged.passUnretained(event)
  }
  return Unmanaged<InputHold>.fromOpaque(userInfo).takeUnretainedValue().receive(type, event)
}

// MARK: - InputHold

/// Holds back every key, click, and scroll the user makes while an Electron target is borrowed, so
/// none of it lands there, and lets it all go, in order, once they are back where they were. Its
/// tap is created after the hotkey listener's, so it sees events first: a hotkey pressed meanwhile
/// is held and replayed like any other key.
final class InputHold: @unchecked Sendable {
  // MARK: Lifecycle

  private init() {}

  // MARK: Internal

  /// Whether the user has done anything since the hold began.
  var isTouched: Bool {
    lock.withLock { !held.isEmpty }
  }

  /// Nil when the tap could not be created.
  static func start() -> InputHold? {
    let hold = InputHold()
    let started = DispatchSemaphore(value: 0)
    let thread = Thread { hold.run(started: started) }
    thread.name = "MiniWhisper Input Hold"
    thread.qualityOfService = .userInteractive
    thread.start()
    started.wait()
    return hold.lock.withLock { hold.tap } == nil ? nil : hold
  }

  /// Ends the hold and replays what it kept into whatever is in front now.
  func release() {
    let runLoop = lock.withLock {
      defer { self.runLoop = nil }
      return self.runLoop
    }
    guard let runLoop else {
      return
    }
    CFRunLoopStop(runLoop)
    finished.wait()
  }

  // MARK: Fileprivate

  fileprivate func receive(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap = lock.withLock({ tap }) {
        CGEvent.tapEnable(tap: tap, enable: true)
      }
      return Unmanaged.passUnretained(event)
    }
    guard event.getIntegerValueField(.eventSourceUserData) != HotkeyListener.syntheticEventMarker,
          let copy = event.copy()
    else {
      return Unmanaged.passUnretained(event)
    }
    lock.withLock { held.append(copy) }
    return nil
  }

  // MARK: Private

  private static let heldTypes: [CGEventType] = [
    .keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp, .leftMouseDragged,
    .rightMouseDown, .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp,
    .otherMouseDragged, .scrollWheel,
  ]
  /// Past this, the user's input goes back to them whatever the delivery is doing: a hold that
  /// outlived its delivery would leave them with a dead keyboard.
  private static let ceiling: CFTimeInterval = 5
  private static let replaySpacing: useconds_t = 1000

  private let lock = NSLock()
  private let finished = DispatchSemaphore(value: 0)
  private var tap: CFMachPort?
  private var runLoop: CFRunLoop?
  private var held: [CGEvent] = []

  private func run(started: DispatchSemaphore) {
    let mask = Self.heldTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
    guard let tap = CGEvent.tapCreate(
      tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
      eventsOfInterest: mask, callback: inputHoldCallback,
      userInfo: Unmanaged.passUnretained(self).toOpaque(),
    ) else {
      started.signal()
      return
    }
    let runLoop = CFRunLoopGetCurrent()
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(runLoop, source, .commonModes)
    lock.withLock {
      self.tap = tap
      self.runLoop = runLoop
    }
    CGEvent.tapEnable(tap: tap, enable: true)
    started.signal()
    CFRunLoopRunInMode(.defaultMode, Self.ceiling, false)

    CGEvent.tapEnable(tap: tap, enable: false)
    CFMachPortInvalidate(tap)
    CFRunLoopRemoveSource(runLoop, source, .commonModes)
    let events = lock.withLock {
      self.runLoop = nil
      defer { held.removeAll() }
      return held
    }
    for event in events {
      event.post(tap: .cghidEventTap)
      usleep(Self.replaySpacing)
    }
    finished.signal()
  }
}
