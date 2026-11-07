import AppKit

// Two helpers for scripts/ui_shot. `windows PID` lists that process's on-screen windows as
// "id layer x y width height", in the global top-left coordinates screencapture -R takes.
// `scroll X Y POINTS` scrolls whatever is under that point, POINTS down (negative is up).
// `backdrop light|dark` covers the main screen with a fixed document or terminal until killed,
// so the pill is captured over the same surface every time instead of whatever is on screen.

func listWindows(pid: pid_t) {
  let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
  for window in windows where window[kCGWindowOwnerPID as String] as? pid_t == pid {
    guard let id = window[kCGWindowNumber as String] as? Int,
          let layer = window[kCGWindowLayer as String] as? Int,
          let bounds = window[kCGWindowBounds as String] as? [String: CGFloat]
    else {
      continue
    }
    let frame = [bounds["X"], bounds["Y"], bounds["Width"], bounds["Height"]].map { Int($0 ?? 0) }
    print(id, layer, frame[0], frame[1], frame[2], frame[3])
  }
}

func scroll(at point: CGPoint, points: Int32) {
  CGWarpMouseCursorPosition(point)
  // Several small steps, the way a trackpad delivers them; one large delta is clamped by some
  // scroll views.
  let step: Int32 = points < 0 ? -40 : 40
  for _ in 0 ..< abs(points / step) {
    let event = CGEvent(
      scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -step, wheel2: 0,
      wheel3: 0,
    )
    event?.location = point
    event?.post(tap: .cghidEventTap)
    usleep(16000)
  }
}

func showBackdrop(isDark: Bool) -> Never {
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  guard let screen = NSScreen.main else {
    preconditionFailure("No main screen to cover")
  }
  let window = NSWindow(
    contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false,
  )
  window.level = .floating
  window.ignoresMouseEvents = true
  window.backgroundColor = isDark
    ? NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    : NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

  let line = isDark
    ? "~/Develop/mini-whisper on main ❯ mise run test:packages   ✓ 412 tests passed in 8.3s"
    : "The quarterly plan settles three questions: what ships first, who owns the rollout, and how we measure whether it worked."
  let text = NSTextField(wrappingLabelWithString: Array(repeating: line, count: 80).joined(separator: "\n"))
  text.font = isDark ? .monospacedSystemFont(ofSize: 13, weight: .regular) : .systemFont(ofSize: 15)
  text.textColor = isDark
    ? NSColor(srgbRed: 0.80, green: 0.82, blue: 0.80, alpha: 1)
    : NSColor(srgbRed: 0.20, green: 0.20, blue: 0.22, alpha: 1)
  text.frame = NSRect(x: 80, y: 0, width: screen.frame.width - 160, height: screen.frame.height)
  window.contentView?.addSubview(text)
  window.orderFrontRegardless()
  app.run()
  exit(0)
}

let arguments = CommandLine.arguments
switch arguments.dropFirst().first {
case "windows":
  guard arguments.count == 3, let pid = pid_t(arguments[2]) else {
    preconditionFailure("usage: windows PID")
  }
  listWindows(pid: pid)
case "scroll":
  guard arguments.count == 5, let x = Double(arguments[2]), let y = Double(arguments[3]),
        let points = Int32(arguments[4])
  else {
    preconditionFailure("usage: scroll X Y POINTS")
  }
  scroll(at: CGPoint(x: x, y: y), points: points)
case "backdrop":
  guard arguments.count == 3, ["light", "dark"].contains(arguments[2]) else {
    preconditionFailure("usage: backdrop light|dark")
  }
  showBackdrop(isDark: arguments[2] == "dark")
default:
  preconditionFailure("usage: windows PID | scroll X Y POINTS | backdrop light|dark")
}
