// Throwaway Accessibility probe for ticket 20. It is deliberately outside the app target.
// Build/run: swiftc -warnings-as-errors -framework AppKit -framework ApplicationServices -framework Foundation ContextCaptureProbe.swift -o .build/context-capture-probe && .build/context-capture-probe 256 [--delay=5] [--activate-chromium]

import AppKit
import ApplicationServices
import Foundation

private struct Timed<Value> {
  var value: Value
  var milliseconds: Double
}

private enum ProbeError: Error, CustomStringConvertible {
  case ax(AXError)
  case missingValue
  case wrongValueType

  var description: String {
    switch self {
    case .ax(let error):
      let name: String
      switch error {
      case .cannotComplete: name = "cannotComplete"
      case .apiDisabled: name = "apiDisabled"
      case .noValue: name = "noValue"
      case .illegalArgument: name = "illegalArgument"
      case .attributeUnsupported: name = "attributeUnsupported"
      case .parameterizedAttributeUnsupported: name = "parameterizedAttributeUnsupported"
      case .notImplemented: name = "notImplemented"
      case .invalidUIElement: name = "invalidUIElement"
      default: name = "unknown"
      }
      return "AXError.\(name) (\(error.rawValue))"
    case .missingValue: return "missing value"
    case .wrongValueType: return "wrong AX value type"
    }
  }
}

private let arguments = Array(CommandLine.arguments.dropFirst())
private let window = Int(arguments.first(where: { Int($0) != nil }) ?? "256")!
private let delay =
  arguments.first(where: { $0.hasPrefix("--delay=") }).flatMap {
    Double($0.dropFirst("--delay=".count))
  } ?? 0
private let activationSettle =
  arguments.first(where: { $0.hasPrefix("--activation-settle=") }).flatMap {
    Double($0.dropFirst("--activation-settle=".count))
  } ?? 1
private let messagingTimeout = arguments.first(where: { $0.hasPrefix("--messaging-timeout=") })
  .flatMap { Float($0.dropFirst("--messaging-timeout=".count)) }
private let pollCount =
  arguments.first(where: { $0.hasPrefix("--poll=") }).flatMap {
    Int($0.dropFirst("--poll=".count))
  } ?? 0
private let pollInterval =
  arguments.first(where: { $0.hasPrefix("--poll-interval=") }).flatMap {
    Double($0.dropFirst("--poll-interval=".count))
  } ?? 0.25
private let system = AXUIElementCreateSystemWide()

// AXUIElementCreateSystemWide's focused-element read fails with cannotComplete on this host
// (macOS 26) even for a trusted process; resolving the frontmost app's PID and asking its app
// element works. This mirrors what production would do anyway (NSWorkspace.frontmostApplication).
private func frontmostApplicationElement() throws -> AXUIElement {
  guard let frontmost = NSWorkspace.shared.frontmostApplication else {
    throw ProbeError.missingValue
  }
  FileHandle.standardOutput.write(
    Data(
      "frontmost app: \(frontmost.localizedName ?? "?") pid=\(frontmost.processIdentifier)\n".utf8))
  return AXUIElementCreateApplication(frontmost.processIdentifier)
}

private func focusedElementViaFrontmostApp() throws -> AXUIElement {
  let application = try frontmostApplicationElement()
  if let messagingTimeout {
    let error = AXUIElementSetMessagingTimeout(application, messagingTimeout)
    guard error == .success else { throw ProbeError.ax(error) }
  }
  return try copiedValue(application, kAXFocusedUIElementAttribute as CFString) as! AXUIElement
}

private func elapsed<Value>(_ body: () throws -> Value) -> Timed<Result<Value, Error>> {
  let clock = ContinuousClock()
  let start = clock.now
  let result: Result<Value, Error>
  do { result = .success(try body()) } catch { result = .failure(error) }
  let duration = start.duration(to: clock.now).components
  return Timed(
    value: result,
    milliseconds: Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
}

private func copiedValue(_ element: AXUIElement, _ attribute: CFString) throws -> CFTypeRef {
  var value: CFTypeRef?
  let error = AXUIElementCopyAttributeValue(element, attribute, &value)
  guard error == .success else { throw ProbeError.ax(error) }
  guard let value else { throw ProbeError.missingValue }
  return value
}

private func copiedString(_ element: AXUIElement, _ attribute: CFString) throws -> String {
  guard let string = try copiedValue(element, attribute) as? String else {
    throw ProbeError.wrongValueType
  }
  return string
}

private func axValue(_ value: CFTypeRef) throws -> AXValue {
  guard CFGetTypeID(value) == AXValueGetTypeID() else { throw ProbeError.wrongValueType }
  return value as! AXValue
}

private func copiedRange(_ element: AXUIElement, _ attribute: CFString) throws -> CFRange {
  let value = try axValue(copiedValue(element, attribute))
  var range = CFRange()
  guard AXValueGetType(value) == .cfRange, AXValueGetValue(value, .cfRange, &range) else {
    throw ProbeError.wrongValueType
  }
  return range
}

private func parameterizedValue(
  _ element: AXUIElement, _ attribute: CFString, _ parameter: CFTypeRef
) throws -> CFTypeRef {
  var value: CFTypeRef?
  let error = AXUIElementCopyParameterizedAttributeValue(element, attribute, parameter, &value)
  guard error == .success else { throw ProbeError.ax(error) }
  guard let value else { throw ProbeError.missingValue }
  return value
}

private func stringForRange(_ element: AXUIElement, _ range: CFRange) throws -> String {
  var query = range
  guard let parameter = AXValueCreate(.cfRange, &query) else { throw ProbeError.wrongValueType }
  guard
    let string = try parameterizedValue(
      element, kAXStringForRangeParameterizedAttribute as CFString, parameter) as? String
  else { throw ProbeError.wrongValueType }
  return string
}

private func lineTextAtInsertionPoint(
  _ element: AXUIElement, _ insertionPoint: Int
) throws -> String {
  let index = NSNumber(value: insertionPoint)
  guard
    let line = try parameterizedValue(
      element, kAXLineForIndexParameterizedAttribute as CFString, index) as? NSNumber
  else { throw ProbeError.wrongValueType }
  let rangeValue = try axValue(
    parameterizedValue(element, kAXRangeForLineParameterizedAttribute as CFString, line))
  var range = CFRange()
  guard AXValueGetType(rangeValue) == .cfRange, AXValueGetValue(rangeValue, .cfRange, &range) else {
    throw ProbeError.wrongValueType
  }
  return try stringForRange(element, range)
}

private func attributeNames(_ element: AXUIElement, parameterized: Bool) throws -> [String] {
  var values: CFArray?
  let error: AXError
  if parameterized {
    error = AXUIElementCopyParameterizedAttributeNames(element, &values)
  } else {
    error = AXUIElementCopyAttributeNames(element, &values)
  }
  guard error == .success else { throw ProbeError.ax(error) }
  return values as? [String] ?? []
}

private func elementPID(_ element: AXUIElement) throws -> pid_t {
  var pid: pid_t = 0
  let error = AXUIElementGetPid(element, &pid)
  guard error == .success else { throw ProbeError.ax(error) }
  return pid
}

private func show<Value>(
  _ name: String, _ timed: Timed<Result<Value, Error>>, render: (Value) -> String
) {
  switch timed.value {
  case .success(let value):
    print("\(name) [\(String(format: "%.3f", timed.milliseconds)) ms]: \(render(value))")
  case .failure(let error):
    print("\(name) [\(String(format: "%.3f", timed.milliseconds)) ms]: ERROR \(error)")
  }
}

private func quoted(_ string: String, maximum: Int = 200) -> String {
  let prefix = String(string.prefix(maximum))
  let suffix = string.count > maximum ? "…" : ""
  return
    "\"\(prefix.replacingOccurrences(of: "\n", with: "\\n"))\(suffix)\" (\(string.utf16.count) UTF-16 units)"
}

// Chromium builds its AX tree lazily; activation must happen BEFORE the focused-element read
// (a focused read against an inactive tree returns noValue), so this targets the frontmost
// app's PID rather than an already-obtained element.
private func activateChromiumAccessibility() {
  guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
    print("Chromium activation: no frontmost app")
    return
  }
  let application = AXUIElementCreateApplication(pid)
  for attribute in ["AXManualAccessibility", "AXEnhancedUserInterface"] as [CFString] {
    let timed = elapsed { AXUIElementSetAttributeValue(application, attribute, kCFBooleanTrue) }
    show("Chromium activation \(attribute)", timed) { String(describing: $0) }
  }
}

// Does anything on the focus chain identify the document being edited? A canvas editor that
// serves stale text is only safely detectable if some ancestor names itself.
private func showIdentity(of element: AXUIElement) {
  var current: AXUIElement? = element
  var level = 0
  while let node = current, level < 8 {
    let role = (try? copiedString(node, kAXRoleAttribute as CFString)) ?? "?"
    let identity = ["AXURL", "AXDocument", "AXTitle", "AXDescription", "AXSubrole"].compactMap {
      attribute -> String? in
      guard let value = try? copiedValue(node, attribute as CFString) else { return nil }
      let rendered =
        (value as? String) ?? (value as? URL)?.absoluteString ?? String(describing: value)
      return "\(attribute)=\(rendered.prefix(120))"
    }
    print("identity[\(level)] role=\(role) \(identity.joined(separator: " "))")
    let parent = try? copiedValue(node, kAXParentAttribute as CFString)
    current = parent.flatMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
    level += 1
  }
}

private func children(of element: AXUIElement) -> [AXUIElement] {
  guard let values = try? copiedValue(element, kAXChildrenAttribute as CFString) as? [Any] else {
    return []
  }
  return values.filter { CFGetTypeID($0 as CFTypeRef) == AXUIElementGetTypeID() }.map {
    $0 as! AXUIElement
  }
}

private func deepestFocusedDescendant(of root: AXUIElement) -> AXUIElement? {
  var pending = [(element: root, depth: 0)]
  var deepest: (element: AXUIElement, depth: Int)?
  while !pending.isEmpty {
    let current = pending.removeFirst()
    if (try? copiedValue(current.element, kAXFocusedAttribute as CFString) as? Bool) == true {
      deepest = current
    }
    pending.append(contentsOf: children(of: current.element).map { ($0, current.depth + 1) })
  }
  return deepest?.element
}

private func wakeFrontmostAccessibilityTree() throws -> Int {
  var pending = [try frontmostApplicationElement()]
  var visited = 0
  while !pending.isEmpty, visited < 5_000 {
    let element = pending.removeFirst()
    visited += 1
    _ = try? copiedValue(element, kAXRoleAttribute as CFString)
    pending.append(contentsOf: children(of: element))
  }
  return visited
}

print(
  "ContextCaptureProbe window=\(window), delay=\(delay)s, activationSettle=\(activationSettle)s, AXIsProcessTrusted=\(AXIsProcessTrusted())"
)
if delay > 0 { Thread.sleep(forTimeInterval: delay) }
if arguments.contains("--activate-chromium") {
  activateChromiumAccessibility()
  Thread.sleep(forTimeInterval: activationSettle)
}
if arguments.contains("--wake-chromium") {
  show("Chromium tree walk", elapsed { try wakeFrontmostAccessibilityTree() }) { "\($0) nodes" }
}
private let systemWideFocused = elapsed {
  try copiedValue(system, kAXFocusedUIElementAttribute as CFString) as! AXUIElement
}
show("focused element (system-wide)", systemWideFocused) { String(describing: $0) }
private let focused: Timed<Result<AXUIElement, Error>> =
  switch systemWideFocused.value {
  case .success: systemWideFocused
  case .failure: elapsed { try focusedElementViaFrontmostApp() }
  }
show("focused element", focused) { String(describing: $0) }
guard case .success(let focusedElement) = focused.value else { exit(1) }
private var element = focusedElement
if (try? copiedString(element, kAXRoleAttribute as CFString)) == "AXWebArea" {
  let descendant = elapsed { deepestFocusedDescendant(of: element) }
  show("deepest AXFocused descendant", descendant) { $0.map { String(describing: $0) } ?? "none" }
  if case .success(let resolved?) = descendant.value { element = resolved }
}
if let messagingTimeout {
  show(
    "focused-element messaging timeout",
    elapsed { AXUIElementSetMessagingTimeout(element, messagingTimeout) }
  ) { String(describing: $0) }
}

show("attributes", elapsed { try attributeNames(element, parameterized: false) }) {
  $0.joined(separator: ", ")
}
show("parameterized attributes", elapsed { try attributeNames(element, parameterized: true) }) {
  $0.joined(separator: ", ")
}
show("role", elapsed { try copiedString(element, kAXRoleAttribute as CFString) }) { quoted($0) }
show("subrole", elapsed { try copiedString(element, kAXSubroleAttribute as CFString) }) {
  quoted($0)
}
show("pid", elapsed { try elementPID(element) }) { String($0) }
show("value", elapsed { try copiedString(element, kAXValueAttribute as CFString) }) { quoted($0) }
show("selected text", elapsed { try copiedString(element, kAXSelectedTextAttribute as CFString) }) {
  quoted($0)
}
show(
  "character count",
  elapsed { try copiedValue(element, kAXNumberOfCharactersAttribute as CFString) as! Int }
) { String($0) }

private let selectedRange = elapsed {
  try copiedRange(element, kAXSelectedTextRangeAttribute as CFString)
}
show("selected range", selectedRange) { "{location: \($0.location), length: \($0.length)}" }

if case .success(let range) = selectedRange.value {
  // Targets reject ranges past the end of the document (AXError -25201) instead of clamping,
  // so the requested window must be clamped to the reported character count.
  let total =
    (try? copiedValue(element, kAXNumberOfCharactersAttribute as CFString)) as? Int ?? Int.max
  let start = max(0, range.location - window)
  let end = min(total, range.location + range.length + window)
  let requested = CFRange(location: start, length: max(0, end - start))
  show(
    "bounded text \(requested.location)..<\(requested.location + requested.length)",
    elapsed { try stringForRange(element, requested) }
  ) { quoted($0) }
  show("insertion-point line", elapsed { try lineTextAtInsertionPoint(element, range.location) }) {
    quoted($0)
  }
}

showIdentity(of: element)

// Staleness measurement: re-read the same element on an interval and stamp each answer, so the
// lag between a keystroke and the AX tree catching up is a measured number.
if pollCount > 0 {
  let formatter = DateFormatter()
  formatter.dateFormat = "HH:mm:ss.SSS"
  for index in 0..<pollCount {
    if index > 0 { Thread.sleep(forTimeInterval: pollInterval) }
    let stamp = formatter.string(from: Date())
    let range = elapsed { try copiedRange(element, kAXSelectedTextRangeAttribute as CFString) }
    let count = elapsed {
      try copiedValue(element, kAXNumberOfCharactersAttribute as CFString) as! Int
    }
    let value = elapsed { try copiedString(element, kAXValueAttribute as CFString) }
    let rangeText: String
    switch range.value {
    case .success(let value): rangeText = "{\(value.location), \(value.length)}"
    case .failure(let error): rangeText = "ERROR \(error)"
    }
    let countText: String
    switch count.value {
    case .success(let value): countText = String(value)
    case .failure(let error): countText = "ERROR \(error)"
    }
    let valueText: String
    switch value.value {
    case .success(let text): valueText = quoted(String(text.suffix(120)))
    case .failure(let error): valueText = "ERROR \(error)"
    }
    print(
      "poll[\(index)] \(stamp) range=\(rangeText) count=\(countText) [\(String(format: "%.3f", value.milliseconds)) ms] tail=\(valueText)"
    )
  }
}
