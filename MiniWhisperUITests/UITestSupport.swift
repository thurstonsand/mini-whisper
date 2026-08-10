import AppKit
import XCTest

/// UI tests only ever drive the Debug product, which keeps its own bundle identifier so that its
/// permission grants never collide with an installed release build.
let debugBundleIdentifier = "com.thurstonsand.MiniWhisper.dev"
/// UI tests drive the dev channel, and user-facing chrome names the running channel.
let appName = "MiniWhisper Dev"

/// Launching a scene, reading what it says about itself, and proving what it painted. Shared by
/// every UI test case so a second suite is a new file rather than a second copy of the plumbing.
extension XCTestCase {
  var agentCommandFileURL: URL {
    FileManager.default.temporaryDirectory.appending(
      path: "miniwhisper-agent-driveability-\(ProcessInfo.processInfo.processIdentifier)",
    )
  }

  var agentResultFileURL: URL {
    URL(fileURLWithPath: "\(agentCommandFileURL.path).result")
  }

  @MainActor func launch(_ scene: String) -> XCUIApplication {
    let app = XCUIApplication()
    parkPointer()
    try? FileManager.default.removeItem(at: agentCommandFileURL)
    try? FileManager.default.removeItem(at: agentResultFileURL)
    app.launchEnvironment["MINIWHISPER_AGENT_SCENE"] = scene
    app.launchEnvironment["MINIWHISPER_AGENT_COMMAND_FILE"] = agentCommandFileURL.path
    app.launch()
    return app
  }

  @MainActor func terminate(_ app: XCUIApplication) {
    app.terminate()
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
  }

  /// The pointer is physical and outlives the app under test, so a scene would otherwise open
  /// underneath whatever the previous case last hovered and report that as its starting state.
  /// Parked bottom-right: the status item lives at the top, and hot corners do not.
  @MainActor private func parkPointer() {
    guard let screen = NSScreen.main?.frame else {
      return
    }
    CGWarpMouseCursorPosition(CGPoint(x: screen.maxX - 2, y: screen.maxY - 2))
  }

  /// The window ignores the first pointer location it is told about, so that a parked pointer
  /// cannot claim mouse mode from the keyboard. A pointer warped in from outside looks exactly
  /// like a parked one on its first sample, so landing somewhere harmless first is what makes the
  /// hover that follows a real move.
  @MainActor func hoverAfterEnteringWindow(_ element: XCUIElement, in app: XCUIApplication) {
    app.outlines["miniwhisper.settings.sidebar"].hover()
    element.hover()
  }

  func postAgentMutation(_ action: String, value: Any) {
    try! "\(UUID().uuidString)|\(action)|\(value)".write(
      to: agentCommandFileURL, atomically: true, encoding: .utf8,
    )
  }

  @MainActor func waitForDisappearance(
    of element: XCUIElement, timeout: TimeInterval = 3,
  ) -> XCTWaiter.Result {
    XCTWaiter.wait(
      for: [
        XCTNSPredicateExpectation(
          predicate: NSPredicate(format: "exists == false"), object: element,
        ),
      ],
      timeout: timeout,
    )
  }

  func waitForAgentResult(_ expected: String, timeout: TimeInterval = 3) {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if (try? String(contentsOf: agentResultFileURL, encoding: .utf8)) == expected {
        return
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    XCTFail("Agent result was not \(expected)")
  }

  func accessibilityValue(_ element: XCUIElement) -> String {
    guard let value = element.value else {
      return ""
    }
    return String(describing: value)
  }

  func assertValue(
    _ expectedValue: String, of element: XCUIElement, file: StaticString = #filePath,
    line: UInt = #line,
  ) {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "value == %@", expectedValue), object: element,
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [expectation], timeout: 3), .completed, file: file, line: line,
    )
    XCTAssertEqual(accessibilityValue(element), expectedValue, file: file, line: line)
  }

  func assertKeyboardFocus(
    on element: XCUIElement, file: StaticString = #filePath, line: UInt = #line,
  ) {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: element,
    )
    XCTAssertEqual(
      XCTWaiter.wait(for: [expectation], timeout: 3), .completed, file: file, line: line,
    )
  }

  /// Focus paint has lied about focus before, so the ring is also checked where it actually lives:
  /// the pixels. Counts the keyboard-focus blue in the element's rectangle plus a hairline margin.
  @MainActor func focusRingPixelCount(
    in screenshot: XCUIScreenshot, around element: XCUIElement, file: StaticString = #filePath,
    line: UInt = #line,
  ) -> Int {
    guard let bitmap = NSBitmapImageRep(data: screenshot.pngRepresentation) else {
      XCTFail("Could not decode screenshot", file: file, line: line)
      return 0
    }
    // The screenshot covers the whole screen; element frames are in screen points, so the ratio
    // between the two is the backing scale whatever display this is running on.
    guard let screenSize = NSScreen.main?.frame.size else {
      XCTFail("Could not resolve the screenshot's screen", file: file, line: line)
      return 0
    }
    let scaleX = CGFloat(bitmap.pixelsWide) / screenSize.width
    let scaleY = CGFloat(bitmap.pixelsHigh) / screenSize.height
    let frame = element.frame.insetBy(dx: -6, dy: -6)
    let minX = max(0, Int(frame.minX * scaleX))
    let maxX = min(bitmap.pixelsWide, Int(frame.maxX * scaleX))
    let minY = max(0, Int(frame.minY * scaleY))
    let maxY = min(bitmap.pixelsHigh, Int(frame.maxY * scaleY))

    var count = 0
    for x in minX ..< maxX {
      for y in minY ..< maxY {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
          continue
        }
        if color.blueComponent > 0.5,
           color.blueComponent - color.redComponent > 0.2,
           color.blueComponent - color.greenComponent > 0.1
        {
          count += 1
        }
      }
    }
    return count
  }

  func recordScreenshot(_ name: String, screenshot: XCUIScreenshot) {
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
