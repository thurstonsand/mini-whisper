// Spike: captures every screen-context source for the frontmost focused window at once, so one
// staged scene can be replayed under each source. The app reads one structured source and falls
// back to OCR; this reads all of them, with the app's own caps and composition:
//
//   meta.json      app, window, focused element, timings
//   field.json     the focused element's value split at the caret (FocusedFieldReader's caps)
//   ax.txt         the Accessibility walk composed exactly as ScreenContextClient composes it
//   ax-lines.json  every line the walk found, with frame, role, and whether it sat in a web area
//   tmux.txt       capture-pane of --tmux-pane on --tmux-socket, trimmed as TmuxPanes.capture is
//   ocr.txt        Vision .accurate on the full-resolution capture, composed as the app does
//   ocr-lines.json every recognized line, with confidence and frame
//   screen.png     the window at full pixel resolution
//   screen-1x.jpg  the window at point size, JPEG 0.8: the copy History keeps and the image arm sends
//
// Usage: screen-collect --out DIR [--tmux-socket PATH --tmux-pane %N]
import AppKit
import ApplicationServices
import FieldContext
import Foundation
import ScreenCaptureKit
import Vision

_ = NSApplication.shared
let arguments = CommandLine.arguments.dropFirst()
func option(_ name: String) -> String? {
  guard let index = arguments.firstIndex(of: "--\(name)") else {
    return nil
  }
  return arguments[arguments.index(after: index)]
}

guard let outPath = option("out") else {
  FileHandle.standardError.write(Data("usage: screen-collect --out DIR [--tmux-socket S --tmux-pane P]\n".utf8))
  exit(2)
}
let out = URL(fileURLWithPath: outPath)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let clock = ContinuousClock()
var timings: [String: Double] = [:]

func milliseconds(_ duration: Duration) -> Double {
  Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
}

@MainActor func timed<T>(_ name: String, _ body: () async throws -> T) async rethrows -> T {
  let started = clock.now
  defer { timings[name] = milliseconds(started.duration(to: clock.now)) }
  return try await body()
}

func write(_ name: String, _ value: some Encodable) throws {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  try encoder.encode(value).write(to: out.appendingPathComponent(name))
}

func write(_ name: String, text: String) throws {
  try Data(text.utf8).write(to: out.appendingPathComponent(name))
}

// MARK: - Accessibility

let messagingTimeout: Float = 0.05

func string(_ element: AXUIElement, _ attribute: String) -> String? {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
    return nil
  }
  return value as? String
}

func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
        let value, CFGetTypeID(value) == AXUIElementGetTypeID()
  else {
    return nil
  }
  return (value as! AXUIElement)
}

func children(_ element: AXUIElement) -> [AXUIElement] {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success
  else {
    return []
  }
  return value as? [AXUIElement] ?? []
}

func frame(of element: AXUIElement) -> CGRect? {
  AXUIElementSetMessagingTimeout(element, messagingTimeout)
  var position: CFTypeRef?
  var size: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success
  else {
    return nil
  }
  var origin = CGPoint.zero
  var extent = CGSize.zero
  AXValueGetValue(position as! AXValue, .cgPoint, &origin)
  AXValueGetValue(size as! AXValue, .cgSize, &extent)
  return CGRect(origin: origin, size: extent)
}

func located(_ element: AXUIElement, _ range: Range<Int>) -> CGRect? {
  var requested = CFRange(location: range.lowerBound, length: range.count)
  var value: CFTypeRef?
  guard let parameter = AXValueCreate(.cfRange, &requested),
        AXUIElementCopyParameterizedAttributeValue(
          element, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &value,
        ) == .success, let value, CFGetTypeID(value) == AXValueGetTypeID()
  else {
    return nil
  }
  var box = CGRect.zero
  return AXValueGetValue(value as! AXValue, .cgRect, &box) ? box : nil
}

func selectedRange(_ element: AXUIElement) -> CFRange? {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value)
    == .success
  else {
    return nil
  }
  var range = CFRange()
  return AXValueGetValue(value as! AXValue, .cfRange, &range) ? range : nil
}

struct Line: Codable {
  let text: String
  let x, y, width, height: Double
  let role: String
  let web: Bool
}

/// ScreenContextClient's walk: depth-first under its node and time caps, text roles as leaves,
/// secure fields and the focused subtree skipped. It also notes each line's role and whether a web
/// area encloses it, so a later eval can compose page text apart from browser chrome.
func walk(
  _ window: AXUIElement, within bounds: CGRect, skipping focused: AXUIElement?,
) -> (lines: [Line], visited: Int, capped: Bool, unplaced: Int) {
  let textRoles: Set<String> = ["AXStaticText", "AXTextArea", "AXTextField"]
  let deadline = clock.now + .milliseconds(400)
  var lines: [Line] = []
  var pending: [(AXUIElement, Bool)] = [(window, false)]
  var visited = 0
  var unplaced = 0
  while let (current, web) = pending.popLast(), visited < 3000, clock.now < deadline {
    visited += 1
    if let focused, CFEqual(current, focused) {
      continue
    }
    AXUIElementSetMessagingTimeout(current, messagingTimeout)
    var inWeb = web
    if let role = string(current, kAXRoleAttribute) {
      let subrole = FieldTargetPolicy.needsSubroleCheck(role: role)
        ? string(current, kAXSubroleAttribute) : nil
      guard !FieldTargetPolicy.isSecure(role: role, subrole: subrole) else {
        continue
      }
      inWeb = inWeb || role == "AXWebArea"
      if textRoles.contains(role) {
        let text = [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute].lazy
          .compactMap { string(current, $0) }.first { !$0.isEmpty }
        if let text, let box = frame(of: current), box.intersects(bounds) {
          guard let rows = VisibleText.rows(
            of: text, in: box, within: bounds,
            locate: { clock.now < deadline ? located(current, $0) : nil },
          ) else {
            unplaced += text.utf16.count
            continue
          }
          for row in rows {
            lines.append(Line(
              text: row.text, x: row.frame.minX, y: row.frame.minY, width: row.frame.width,
              height: row.frame.height, role: role, web: inWeb,
            ))
          }
        }
        continue
      }
    }
    pending += children(current).reversed().map { ($0, inWeb) }
  }
  return (lines, visited, visited >= 3000 || clock.now >= deadline, unplaced)
}

func visible(_ lines: [Line]) -> [VisibleLine] {
  lines.map { VisibleLine(text: $0.text, frame: CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height)) }
}

// MARK: - Target

guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else {
  fatalError("needs Accessibility and a frontmost app")
}
let root = AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetMessagingTimeout(root, 0.5)
// Chromium and Electron build their tree only for a client that asks for it.
AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
AXUIElementSetAttributeValue(root, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
guard let window = element(root, kAXFocusedWindowAttribute), let bounds = frame(of: window) else {
  fatalError("frontmost app has no focused window")
}
let focused = element(root, kAXFocusedUIElementAttribute)
let isTerminal = TerminalBundleIDs.contains(app.bundleIdentifier)
let focus = isTerminal ? nil : focused.flatMap { frame(of: $0) }

struct Field: Codable {
  let role: String?
  let before, selected, after: String
}

var field: Field?
if let focused, !isTerminal, let value = string(focused, kAXValueAttribute),
   let range = selectedRange(focused)
{
  let units = Array(value.utf16)
  let start = max(0, min(range.location, units.count))
  let end = max(start, min(range.location + range.length, units.count))
  func text(_ slice: ArraySlice<UInt16>) -> String { String(decoding: slice, as: UTF16.self) }
  field = Field(
    role: string(focused, kAXRoleAttribute),
    before: text(units[max(0, start - 256) ..< start]),
    selected: text(units[start ..< min(end, start + 1024)]),
    after: text(units[end ..< min(units.count, end + 256)]),
  )
}
try write("field.json", field)

// MARK: - Accessibility text

// The app walks a process's first read twice, 300 ms apart; collection always reads warm.
_ = walk(window, within: bounds, skipping: isTerminal ? nil : focused)
try await Task.sleep(for: .milliseconds(300))
let ax = await timed("ax") { walk(window, within: bounds, skipping: isTerminal ? nil : focused) }
try write("ax-lines.json", ax.lines)
try write("ax.txt", text: VisibleText.compose(
  VisibleText.joiningRuns(visible(ax.lines)), within: bounds, excluding: focus,
))

// MARK: - tmux

if let socket = option("tmux-socket"), let pane = option("tmux-pane") {
  let text = await timed("tmux") { () -> String in
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["tmux", "-S", socket, "capture-pane", "-p", "-J", "-t", pane]
    let pipe = Pipe()
    process.standardOutput = pipe
    try? process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    var rows = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
      .map { $0.replacing(#/\s+$/#, with: "") }
    while rows.last?.isEmpty == true {
      rows.removeLast()
    }
    while rows.reduce(0, { $0 + $1.utf16.count + 1 }) > VisibleText.budget + 1, !rows.isEmpty {
      rows.removeFirst()
    }
    return rows.joined(separator: "\n")
  }
  try write("tmux.txt", text: text)
}

// MARK: - Screenshot

let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
let axTitle = string(window, kAXTitleAttribute)
let candidates = content.windows.filter {
  $0.owningApplication?.processID == app.processIdentifier
    && abs($0.frame.minX - bounds.minX) < 1 && abs($0.frame.minY - bounds.minY) < 1
    && abs($0.frame.width - bounds.width) < 1 && abs($0.frame.height - bounds.height) < 1
}
// Maximized windows of one app share a frame, so the title decides between them.
let named = candidates.first { candidate in
  guard let shown = candidate.title, !shown.isEmpty, let axTitle else { return false }
  return axTitle == shown || axTitle.hasPrefix(shown + " - ")
}
guard let scWindow = named ?? candidates.first else {
  fatalError("no SCWindow matches the focused window \(bounds)")
}
let filter = SCContentFilter(desktopIndependentWindow: scWindow)
let configuration = SCStreamConfiguration()
configuration.width = Int(bounds.width * CGFloat(filter.pointPixelScale))
configuration.height = Int(bounds.height * CGFloat(filter.pointPixelScale))
configuration.showsCursor = false
let image = try await timed("screenshot") {
  try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
}
try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
  .write(to: out.appendingPathComponent("screen.png"))
let small = CGContext(
  data: nil, width: Int(bounds.width), height: Int(bounds.height), bitsPerComponent: 8,
  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
)!
small.interpolationQuality = .high
small.draw(image, in: CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height))
try NSBitmapImageRep(cgImage: small.makeImage()!)
  .representation(using: .jpeg, properties: [.compressionFactor: 0.8])!
  .write(to: out.appendingPathComponent("screen-1x.jpg"))

// MARK: - OCR

struct Recognized: Codable {
  let text: String
  let confidence: Float
  let x, y, width, height: Double
}

var request = RecognizeTextRequest()
request.recognitionLevel = .accurate
request.recognitionLanguages = [Locale.Language(identifier: "en-US")]
request.usesLanguageCorrection = true
let observations = try await timed("ocr") { try await request.perform(on: image) }
let recognized = observations.compactMap { observation -> Recognized? in
  guard let candidate = observation.topCandidates(1).first else {
    return nil
  }
  let box = observation.boundingBox.cgRect
  return Recognized(
    text: candidate.string, confidence: candidate.confidence,
    x: bounds.minX + box.minX * bounds.width, y: bounds.minY + (1 - box.maxY) * bounds.height,
    width: box.width * bounds.width, height: box.height * bounds.height,
  )
}
.sorted { abs($0.y - $1.y) > 4 ? $0.y < $1.y : $0.x < $1.x }
try write("ocr-lines.json", recognized)
try write("ocr.txt", text: VisibleText.compose(
  recognized.map { VisibleLine(text: $0.text, frame: CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height)) },
  within: bounds, excluding: focus,
))

// MARK: - Meta

struct Meta: Codable {
  let bundleID: String?
  let appName: String?
  let windowTitle: String?
  let windowFrame: [Double]
  let focusedRole: String?
  let focusedFrame: [Double]?
  let axVisited: Int
  let axCapped: Bool
  /// UTF-16 units of text the walk found but could not place; the app's read falls to OCR then.
  let axUnplaced: Int
  let screenshotTitle: String?
  let screenshotCandidates: Int
  let capturedAt: Date
  let timingsMs: [String: Double]
}

try write("meta.json", Meta(
  bundleID: app.bundleIdentifier, appName: app.localizedName, windowTitle: string(window, kAXTitleAttribute),
  windowFrame: [bounds.minX, bounds.minY, bounds.width, bounds.height],
  focusedRole: focused.flatMap { string($0, kAXRoleAttribute) },
  focusedFrame: focused.flatMap { frame(of: $0) }.map { [$0.minX, $0.minY, $0.width, $0.height] },
  axVisited: ax.visited, axCapped: ax.capped, axUnplaced: ax.unplaced, screenshotTitle: scWindow.title,
  screenshotCandidates: candidates.count, capturedAt: Date(), timingsMs: timings,
))
print("\(app.bundleIdentifier ?? "?") ax=\(ax.lines.count) lines visited=\(ax.visited) ocr=\(recognized.count) lines \(timings)")
