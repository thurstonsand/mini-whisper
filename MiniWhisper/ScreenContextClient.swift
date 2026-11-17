import AppKit
import ApplicationServices
import AppSettings
import ComposableArchitecture
import FieldContext
import Foundation
import History
import os
import OSLog
import ScreenCaptureKit
import Vision

// MARK: - ScreenCapture

/// What Expanded context read at the press: the text the cleanup pass is given and the screenshot
/// it was recognized from, which only History keeps — or, in Screenshot mode, the screenshot
/// alone, which cleanup is shown in place of the text.
struct ScreenCapture: Equatable {
  static let empty = ScreenCapture(context: nil, screenshot: nil, showsScreenshot: false)

  var context: ScreenContext?
  /// A JPEG of the target window at its point size; nil without Screen Recording.
  var screenshot: Data?
  var showsScreenshot: Bool

  var cleanupScreenshot: Data? {
    showsScreenshot ? screenshot : nil
  }
}

// MARK: - ScreenContextClient

/// Reads what is on screen around a target. It runs at the press, while the user is still
/// speaking, so it can afford what delivery cannot: a whole window's Accessibility tree, a
/// screenshot, and Vision's accurate recognizer.
@DependencyClient struct ScreenContextClient {
  var capture: @Sendable (DeliveryTarget, ScreenContextMode) async -> ScreenCapture = { _, _ in
    .empty
  }

  var hasScreenRecording: @Sendable () async -> Bool = { false }
  /// Opens System Settings at Screen Recording, where the grant is made.
  var requestScreenRecording: @Sendable () async -> Void
}

// MARK: DependencyKey

extension ScreenContextClient: DependencyKey {
  static let testValue = Self(
    capture: { _, _ in .empty }, hasScreenRecording: { true }, requestScreenRecording: {},
  )

  static let liveValue = Self(
    capture: { target, mode in
      let clock = ContinuousClock()
      let started = clock.now
      // A dictation's cleanup waits on this, so the deadline has to hold even against a read
      // that ignores cancellation — an AX call into a wedged app, a tmux that never answers.
      // Whichever finishes first answers; the other is abandoned.
      let (answers, answer) = AsyncStream.makeStream(of: ScreenCapture?.self)
      let read = Task { await answer.yield(ScreenReader.read(target, mode: mode)) }
      let expiry = Task {
        try? await Task.sleep(for: ScreenReader.deadline)
        answer.yield(nil)
      }
      var first = answers.makeAsyncIterator()
      let settled = await first.next() ?? nil
      read.cancel()
      expiry.cancel()
      answer.finish()
      let elapsed = started.duration(to: clock.now).milliseconds
      guard let capture = settled else {
        contextLogger.notice(
          "Screen capture timed out elapsed=\(elapsed, format: .fixed(precision: 1))ms",
        )
        return .empty
      }
      contextLogger.info(
        "Screen capture \(capture.logDescription, privacy: .public) elapsed=\(elapsed, format: .fixed(precision: 1))ms",
      )
      return capture
    },
    hasScreenRecording: {
      CGPreflightScreenCaptureAccess() ? true : await ScreenReader.shareableContent() != nil
    },
    requestScreenRecording: { await askForScreenRecording() },
  )
}

/// The request lists the app in System Settings, where the grant is made; macOS shows its own
/// alert only the first time, and that alert only points there too.
@MainActor private func askForScreenRecording() {
  ScreenReader.hasAsked.withLock { $0 = true }
  guard !CGRequestScreenCaptureAccess() else {
    return
  }
  NSWorkspace.shared.open(SystemSettingsPane.screenRecording)
}

extension DependencyValues {
  var screenContext: ScreenContextClient {
    get { self[ScreenContextClient.self] }
    set { self[ScreenContextClient.self] = newValue }
  }
}

// MARK: - ScreenReader

private enum ScreenReader {
  // MARK: Internal

  /// Counted from the moment the target is known, just after the press, so only a dictation
  /// about this short can be kept waiting by it.
  static let deadline = Duration.seconds(2)

  /// Set once this process has asked for Screen Recording, after which macOS has its answer.
  static let hasAsked = OSAllocatedUnfairLock(initialState: false)

  /// Screenshot mode sends the window's image in place of its text, so with one in hand nothing
  /// else is read; without a window to match, it reads text as Text does. Expanded context reads
  /// nothing without Screen Recording, even where the Accessibility tree alone could answer: it
  /// either works on every window or asks for the grant.
  static func read(_ target: DeliveryTarget, mode: ScreenContextMode) async -> ScreenCapture {
    guard AXIsProcessTrusted(), let processID = target.processID, let window = target.window,
          let content = await shareableContent()
    else {
      return .empty
    }
    let bounds = frame(of: window.raw)
    // A terminal's focused element is its whole screen, which is the context rather than a field
    // to leave out of it.
    let excludesFocus = !TerminalBundleIDs.contains(target.app?.bundleID)
    let focus = excludesFocus ? target.element.flatMap { frame(of: $0.raw) } : nil

    var image: CGImage?
    var screenshot: Data?
    if let bounds,
       let captured = await self.screenshot(
         of: processID, frame: bounds, title: target.title, in: content,
       )
    {
      image = captured
      screenshot = jpeg(captured, pointSize: bounds.size)
    }
    if mode == .screenshot, screenshot != nil {
      return ScreenCapture(context: nil, screenshot: screenshot, showsScreenshot: true)
    }

    let structured: ScreenContext.StructuredText? =
      if let pane = target.pane {
        TmuxPanes.capture(pane, budget: VisibleText.budget).map {
          .init(source: .tmux, text: $0)
        }
      } else if let bounds {
        await accessibilityText(
          of: processID, in: window.raw, bounds: bounds,
          skipping: excludesFocus ? target.element : nil, focus: focus, canRecognize: image != nil,
        )
      } else {
        nil
      }

    // Recognized text drops what the target reports exactly — diacritics, the text scrolled out
    // of view — so it is read only for a target that reported nothing.
    var recognized: String?
    if structured == nil, let image, let bounds {
      recognized = await recognizedText(in: image, frame: bounds, focus: focus)
    }

    guard structured != nil || recognized != nil else {
      return ScreenCapture(context: nil, screenshot: screenshot, showsScreenshot: false)
    }
    return ScreenCapture(
      context: ScreenContext(
        windowTitle: target.title, structured: structured, recognizedText: recognized,
      ),
      screenshot: screenshot, showsScreenshot: false,
    )
  }

  /// Doubles as the check for Screen Recording, which it fails without.
  /// CGPreflightScreenCaptureAccess keeps the answer it had at launch, so a grant made in System
  /// Settings since then would wait on "Quit & Reopen"; ScreenCaptureKit answers from the grant as
  /// it stands. But asked before the app ever has, ScreenCaptureKit raises macOS's alert itself,
  /// so it is left alone until preflight says yes or this process has asked, which is how a grant
  /// preflight has not seen arrives; one made without asking shows after a relaunch.
  static func shareableContent() async -> SCShareableContent? {
    guard CGPreflightScreenCaptureAccess() || hasAsked.withLock({ $0 }) else {
      return nil
    }
    return try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
  }

  // MARK: Private

  private static let messagingTimeout: Float = 0.05
  private static let maximumNodes = 3000
  private static let walkBudget = Duration.milliseconds(400)
  private static let treeBuildSettle = Duration.milliseconds(300)
  private static let ledger = ReadLedger()
  /// Leaves that carry their own text. Buttons and menus are left out: their titles are the
  /// app's chrome, which names nothing the user is talking about.
  private static let textRoles: Set<String> = ["AXStaticText", "AXTextArea", "AXTextField"]

  /// Safari builds a page's tree only once something asks for it, so the first walk of a process
  /// nobody has read yet finds the window's chrome and no page — 25 nodes where a warm read finds
  /// 55, measured against a freshly opened Safari. That walk is the asking; the next one, once the
  /// page has had a moment to answer it, reads what it built.
  ///
  /// Text the walk could not place on screen, such as VS Code's editor, is left out. When there is
  /// a screenshot to recognize, its text covers that text and so stands in for the whole read;
  /// without one, what was placed is all there is.
  private static func accessibilityText(
    of processID: pid_t, in window: AXUIElement, bounds: CGRect, skipping focused: AXElement?,
    focus: CGRect?, canRecognize: Bool,
  ) async -> ScreenContext.StructuredText? {
    if await ledger.isFirstRead(of: processID) {
      _ = walk(window, within: bounds, skipping: focused)
      try? await Task.sleep(for: treeBuildSettle)
    }
    let read = walk(window, within: bounds, skipping: focused)
    guard !read.unplaced || !canRecognize else {
      return nil
    }
    let text = VisibleText.compose(
      VisibleText.joiningRuns(read.lines), within: bounds, excluding: focus,
    )
    return text.isEmpty ? nil : .init(source: .accessibility, text: text)
  }

  /// Depth-first, so a page reads in document order — the sidebar, then the conversation, then
  /// the composer — rather than interleaved row by row as sorting by position would have it.
  private static func walk(
    _ window: AXUIElement, within bounds: CGRect, skipping focused: AXElement?,
  ) -> (lines: [VisibleLine], unplaced: Bool) {
    let clock = ContinuousClock()
    let deadline = clock.now + walkBudget
    var lines: [VisibleLine] = []
    var unplaced = false
    var pending = [window]
    var visited = 0
    while let element = pending.popLast(), visited < maximumNodes, clock.now < deadline {
      visited += 1
      if let focused, CFEqual(element, focused.raw) {
        continue
      }
      AXUIElementSetMessagingTimeout(element, messagingTimeout)
      if let role = try? AXRead.string(element, kAXRoleAttribute).get() {
        let subrole = FieldTargetPolicy.needsSubroleCheck(role: role)
          ? try? AXRead.string(element, kAXSubroleAttribute).get() : nil
        guard !FieldTargetPolicy.isSecure(role: role, subrole: subrole) else {
          continue
        }
        if textRoles.contains(role) {
          if let text = text(of: element), let frame = frame(of: element),
             frame.intersects(bounds)
          {
            // Locating rows is one call into the app per row, so it stops with the walk.
            let rows = VisibleText.rows(
              of: text, in: frame, within: bounds,
              locate: { range in
                guard clock.now < deadline else {
                  return nil
                }
                return try? AXRead.bounds(
                  element, CFRange(location: range.lowerBound, length: range.count),
                )
                .get()
              },
            )
            if let rows {
              lines += rows
            } else {
              unplaced = true
            }
          }
          continue
        }
      }
      pending += ((try? AXRead.children(element).get()) ?? []).reversed()
    }
    return (lines, unplaced)
  }

  private static func text(of element: AXUIElement) -> String? {
    for attribute in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
      if let text = try? AXRead.string(element, attribute).get(), !text.isEmpty {
        return text
      }
    }
    return nil
  }

  private static func frame(of element: AXUIElement) -> CGRect? {
    AXUIElementSetMessagingTimeout(element, messagingTimeout)
    guard case let .success(position) = AXRead.value(element, kAXPositionAttribute),
          case let .success(size) = AXRead.value(element, kAXSizeAttribute)
    else {
      return nil
    }
    var origin = CGPoint.zero
    var extent = CGSize.zero
    guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
          AXValueGetValue(size as! AXValue, .cgSize, &extent)
    else {
      return nil
    }
    return CGRect(origin: origin, size: extent)
  }

  /// The window alone, never the rectangle it occupies: the pill is on screen by now, and so may
  /// be anything else that overlaps the target. ScreenCaptureKit has no focused-window selector,
  /// so the AX window is matched to its `SCWindow` by owner and frame, and by title among
  /// windows that share a frame: an app's maximized windows all do.
  private static func screenshot(
    of processID: pid_t, frame: CGRect, title: String?, in content: SCShareableContent,
  ) async -> CGImage? {
    let candidates = content.windows.filter {
      $0.owningApplication?.processID == processID
        && abs($0.frame.minX - frame.minX) < 1 && abs($0.frame.minY - frame.minY) < 1
        && abs($0.frame.width - frame.width) < 1 && abs($0.frame.height - frame.height) < 1
    }
    // Chrome's Accessibility title appends the app's name to the tab title its window carries.
    let named = candidates.first { candidate in
      guard let shown = candidate.title, !shown.isEmpty, let title else {
        return false
      }
      return title == shown || title.hasPrefix(shown + " - ")
    }
    guard let window = named ?? candidates.first else {
      return nil
    }
    let filter = SCContentFilter(desktopIndependentWindow: window)
    let configuration = SCStreamConfiguration()
    // Full pixel resolution for the recognizer; the stored copy is scaled down afterwards.
    configuration.width = Int(frame.width * CGFloat(filter.pointPixelScale))
    configuration.height = Int(frame.height * CGFloat(filter.pointPixelScale))
    configuration.showsCursor = false
    return try? await SCScreenshotManager.captureImage(
      contentFilter: filter, configuration: configuration,
    )
  }

  /// Points, not pixels: a model given a Retina screenshot reads it no better and is charged for
  /// it twice over, as the screen-context spike measured.
  private static func jpeg(_ image: CGImage, pointSize: CGSize) -> Data? {
    let width = Int(pointSize.width)
    let height = Int(pointSize.height)
    guard let context = CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
    ) else {
      return nil
    }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let scaled = context.makeImage() else {
      return nil
    }
    return NSBitmapImageRep(cgImage: scaled)
      .representation(using: .jpeg, properties: [.compressionFactor: 0.8])
  }

  private static func recognizedText(
    in image: CGImage, frame: CGRect, focus: CGRect?,
  ) async -> String? {
    var request = RecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = [Locale.Language(identifier: "en-US")]
    request.usesLanguageCorrection = true
    guard let observations = try? await request.perform(on: image) else {
      return nil
    }
    // Vision's boxes are normalized with a bottom-left origin; AX frames are global points with
    // a top-left one, and the field's frame is in the latter.
    let lines = observations.compactMap { observation -> VisibleLine? in
      guard let text = observation.topCandidates(1).first?.string else {
        return nil
      }
      let box = observation.boundingBox.cgRect
      return VisibleLine(
        text: text,
        frame: CGRect(
          x: frame.minX + box.minX * frame.width, y: frame.minY + (1 - box.maxY) * frame.height,
          width: box.width * frame.width, height: box.height * frame.height,
        ),
      )
    }
    .sorted { abs($0.frame.minY - $1.frame.minY) > 4 ? $0.frame.minY < $1.frame.minY : $0.frame
      .minX < $1.frame.minX
    }
    let text = VisibleText.compose(lines, within: frame, excluding: focus)
    return text.isEmpty ? nil : text
  }
}

private extension Duration {
  var milliseconds: Double {
    let parts = components
    return Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
  }
}

// MARK: - ReadLedger

/// The processes whose trees a read has already woken. A recycled process ID skips one wake,
/// which costs that one dictation its page; tracking launch dates would not be worth it.
private actor ReadLedger {
  // MARK: Internal

  func isFirstRead(of processID: pid_t) -> Bool {
    read.insert(processID).inserted
  }

  // MARK: Private

  private var read: Set<pid_t> = []
}

extension ScreenCapture {
  /// Log-safe: sources and lengths, never screen text.
  var logDescription: String {
    let structured = context?.structured.map { "\($0.source.rawValue)=\($0.text.utf16.count)" }
      ?? "structured=none"
    let recognized = context?.recognizedText.map { "ocr=\($0.utf16.count)" } ?? "ocr=none"
    let screenshot = screenshot.map { "jpeg=\($0.count)" } ?? "jpeg=none"
    return "\(structured) \(recognized) \(screenshot) shown=\(showsScreenshot)"
  }
}
