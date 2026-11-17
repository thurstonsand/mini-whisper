// Disposable probe: one-shot screen capture plus local Vision OCR, timed per stage.
// Not an Xcode target; see README.md.
import AppKit
import ApplicationServices
import CoreGraphics
import CoreML
import Foundation
import ScreenCaptureKit
import Vision

func ms(_ d: Duration) -> String {
  let c = d.components
  return String(format: "%.1fms", Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15)
}

let arguments = CommandLine.arguments.dropFirst()
func option(_ name: String) -> String? {
  arguments.first { $0.hasPrefix("--\(name)=") }.map { String($0.dropFirst(name.count + 3)) }
}

let mode = option("mode") ?? "window"  // window | rect | display
let save = option("save")
let levels = (option("levels") ?? "accurate,fast").split(separator: ",").map(String.init)
let clock = ContinuousClock()

/// The focused window's frame, from AX — ScreenCaptureKit has no "frontmost window" selector.
func focusedWindow() -> (pid: pid_t, frame: CGRect, title: String)? {
  guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
  let root = AXUIElementCreateApplication(app.processIdentifier)
  var window: CFTypeRef?
  guard AXUIElementCopyAttributeValue(root, kAXFocusedWindowAttribute as CFString, &window) == .success
  else { return nil }
  let element = window as! AXUIElement
  var position: CFTypeRef?
  var size: CFTypeRef?
  var title: CFTypeRef?
  AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position)
  AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size)
  AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
  var origin = CGPoint.zero
  var extent = CGSize.zero
  AXValueGetValue(position as! AXValue, .cgPoint, &origin)
  AXValueGetValue(size as! AXValue, .cgSize, &extent)
  return (app.processIdentifier, CGRect(origin: origin, size: extent), title as? String ?? "")
}

func capture() async throws -> CGImage {
  let started = clock.now
  defer { print("capture[\(mode)] \(ms(started.duration(to: clock.now)))") }
  switch mode {
  case "rect":
    // macOS 15.2+: acquires only the rectangle, no shareable-content enumeration.
    guard let window = focusedWindow() else { throw CocoaError(.featureUnsupported) }
    print("rect \(window.frame) title=\(window.title)")
    return try await SCScreenshotManager.captureImage(in: window.frame)
  case "display":
    let content = try await SCShareableContent.current
    let display = content.displays[0]
    let filter = SCContentFilter(display: display, excludingWindows: [])
    let config = SCStreamConfiguration()
    config.width = display.width * 2
    config.height = display.height * 2
    return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
  default:
    let enumerated = clock.now
    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    print("shareable-content \(ms(enumerated.duration(to: clock.now))) windows=\(content.windows.count)")
    guard let focused = focusedWindow() else { throw CocoaError(.featureUnsupported) }
    // Bridge AX → SCWindow by owner PID and frame; one app can own several windows.
    guard let window = content.windows.first(where: {
      $0.owningApplication?.processID == focused.pid && $0.frame == focused.frame
    }) else { throw CocoaError(.fileNoSuchFile) }
    print("window id=\(window.windowID) frame=\(window.frame) title=\(window.title ?? "")")
    let filter = SCContentFilter(desktopIndependentWindow: window)
    let config = SCStreamConfiguration()
    config.width = Int(window.frame.width * CGFloat(filter.pointPixelScale))
    config.height = Int(window.frame.height * CGFloat(filter.pointPixelScale))
    config.showsCursor = false
    return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
  }
}

/// `--cpu` forces the legacy request onto the CPU: a virtualized Mac has no Neural Engine, and
/// the default device fails to compile Vision's model there.
let cpuOnly = arguments.contains("--cpu")

func recognize(_ image: CGImage, level: String) async throws {
  let started = clock.now
  let lines: [(String, Float, CGRect)]
  if cpuOnly {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = level == "fast" ? .fast : .accurate
    request.recognitionLanguages = ["en-US"]
    request.usesLanguageCorrection = level != "fast"
    for (stage, _) in try request.supportedComputeStageDevices {
      request.setComputeDevice(MLComputeDevice.allComputeDevices.first { device in
        if case .cpu = device { return true }
        return false
      }, for: stage)
    }
    try VNImageRequestHandler(cgImage: image).perform([request])
    lines = (request.results ?? []).compactMap { observation in
      guard let top = observation.topCandidates(1).first else { return nil }
      return (top.string, top.confidence, observation.boundingBox)
    }
  } else {
    var request = RecognizeTextRequest()
    request.recognitionLevel = level == "fast" ? .fast : .accurate
    request.recognitionLanguages = [Locale.Language(identifier: "en-US")]
    request.usesLanguageCorrection = level != "fast"
    lines = try await request.perform(on: image).compactMap { observation in
      guard let top = observation.topCandidates(1).first else { return nil }
      return (top.string, top.confidence, observation.boundingBox.cgRect)
    }
  }
  let elapsed = started.duration(to: clock.now)
  let characters = lines.reduce(0) { $0 + $1.0.count }
  print("ocr[\(level)] \(ms(elapsed)) lines=\(lines.count) chars=\(characters)")
  guard level == levels.first else { return }
  // Vision's origin is bottom-left; sort top-to-bottom, then left-to-right, for reading order.
  for (text, confidence, box) in lines.sorted(by: {
    abs($0.2.maxY - $1.2.maxY) > 0.01 ? $0.2.maxY > $1.2.maxY : $0.2.minX < $1.2.minX
  }) {
    print(String(format: "  %.2f y=%.3f x=%.3f | ", confidence, box.maxY, box.minX) + text)
  }
}

// A CLI has no window-server connection until AppKit makes one; capture asserts without it.
_ = NSApplication.shared
setvbuf(stdout, nil, _IOLBF, 0)
print("screen-recording preflight=\(CGPreflightScreenCaptureAccess())")
let image = try await capture()
print("image \(image.width)x\(image.height)")
if let save {
  let rep = NSBitmapImageRep(cgImage: image)
  try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: save))
  let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7])!
  try jpeg.write(to: URL(fileURLWithPath: save + ".jpg"))
  print("saved png=\(save) jpeg-bytes=\(jpeg.count)")
}
for level in levels {
  try await recognize(image, level: level)
}
