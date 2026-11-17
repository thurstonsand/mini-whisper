// Disposable probe: walk the frontmost app's focused window and collect text it exposes, with
// the focused element marked, under node and time caps. Not an Xcode target; see README.md.
import AppKit
import ApplicationServices
import Foundation

let arguments = CommandLine.arguments.dropFirst()
func option(_ name: String) -> String? {
  arguments.first { $0.hasPrefix("--\(name)=") }.map { String($0.dropFirst(name.count + 3)) }
}

let maximumNodes = Int(option("nodes") ?? "2000")!
let budget = Duration.milliseconds(Int(option("budget-ms") ?? "250")!)
let maximumText = Int(option("text-cap") ?? "400")!
let clock = ContinuousClock()

func read(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
  var value: CFTypeRef?
  return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
}

guard let app = NSWorkspace.shared.frontmostApplication else { fatalError("no frontmost app") }
let root = AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetMessagingTimeout(root, 0.05)
let started = clock.now
guard let window = read(root, kAXFocusedWindowAttribute).map({ $0 as! AXUIElement }) else {
  fatalError("no focused window")
}
let focused = read(root, kAXFocusedUIElementAttribute).map { $0 as! AXUIElement }
print("app=\(app.bundleIdentifier ?? "?") title=\(read(window, kAXTitleAttribute) as? String ?? "")")

let textRoles: Set<String> = [
  "AXStaticText", "AXTextArea", "AXTextField", "AXHeading", "AXLink", "AXCell", "AXButton",
  "AXMenuButton", "AXRadioButton", "AXTab",
]
var visited = 0
var collected = 0
var pending: [(AXUIElement, Int)] = [(window, 0)]
var stopReason = "exhausted"
while !pending.isEmpty {
  guard visited < maximumNodes else { stopReason = "node cap"; break }
  guard started.duration(to: clock.now) < budget else { stopReason = "time budget"; break }
  let (element, depth) = pending.removeFirst()
  visited += 1
  AXUIElementSetMessagingTimeout(element, 0.02)
  let role = read(element, kAXRoleAttribute) as? String ?? "?"
  if role == "AXSecureTextField" { continue }
  if textRoles.contains(role) {
    let value = read(element, kAXValueAttribute) as? String
    let title = read(element, kAXTitleAttribute) as? String
    let description = read(element, kAXDescriptionAttribute) as? String
    let text = [value, title, description].compactMap { $0 }.first { !$0.isEmpty }
    if let text {
      collected += text.utf16.count
      let isFocused = focused.map { CFEqual($0, element) } ?? false
      let shown = text.replacingOccurrences(of: "\n", with: "⏎").prefix(maximumText)
      print("\(isFocused ? "*" : " ") d=\(depth) \(role) [\(text.utf16.count)] \(shown)")
    }
  }
  // Not AXVisibleChildren: a Safari window does not answer it at all.
  let children = read(element, kAXChildrenAttribute)
  for child in (children as? [AXUIElement]) ?? [] {
    pending.append((child, depth + 1))
  }
}
let elapsed = started.duration(to: clock.now).components
print(String(
  format: "visited=%d text-units=%d stop=%@ elapsed=%.1fms", visited, collected, stopReason,
  Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15,
))
