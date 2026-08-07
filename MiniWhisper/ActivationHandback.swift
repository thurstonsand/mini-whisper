import AppKit

/// An accessory app that activates itself for a window owes the focus back when that window
/// closes; without this, key focus sits in limbo until the user clicks. A rolling observer
/// remembers the last frontmost app that was not us (Rectangle's shape) — a one-time snapshot
/// goes stale when the user visits another app and returns by clicking the window — and the
/// give-back yields cooperatively before activating it (Ice's mechanism).
@MainActor final class ActivationHandback {
  // MARK: Lifecycle

  init() {
    observer = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main,
    ) { _ in
      MainActor.assumeIsolated {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else {
          return
        }
        Self.previousApp = app
      }
    }
  }

  isolated deinit {
    if let observer {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }
  }

  // MARK: Internal

  func giveBack() {
    // If the user already switched apps on their own, focus is not ours to hand out.
    guard NSApp.isActive, let previousApp = Self.previousApp, !previousApp.isTerminated else {
      return
    }
    NSApp.yieldActivation(to: previousApp)
    previousApp.activate()
  }

  // MARK: Private

  /// One truth shared by every window: whichever app the user was in last, regardless of which
  /// of our windows is closing.
  private static var previousApp: NSRunningApplication?

  private var observer: (any NSObjectProtocol)?
}
