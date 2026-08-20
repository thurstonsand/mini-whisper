import AppKit
import ObjectiveC.runtime
import XCTest

// MARK: - Quiescence

/// After every synthesized event, XCTest waits for the app to report itself idle — animations
/// finished, run loop drained — before returning. That wait costs 200–400 ms per keystroke and
/// buys synchronization this suite does not use: every claim here is polled until it holds, so
/// idle-ness proves nothing a poll does not. The wait is disabled by replacing the private
/// quiescence methods with no-ops; if an Xcode update renames them, the suite gets slower but
/// stays correct, and the unmatched-selector assertion below says so.
enum Quiescence {
  static let disabled: Bool = {
    guard let processClass = objc_getClass("XCUIApplicationProcess") as? AnyClass else {
      return false
    }
    var matched = false
    for selector in [
      "waitForQuiescenceIncludingAnimationsIdle:",
      "waitForQuiescenceIncludingAnimationsIdle:isPreEvent:",
    ] {
      guard let method = class_getInstanceMethod(processClass, NSSelectorFromString(selector))
      else {
        continue
      }
      let noop: @convention(block) (AnyObject, Bool, Bool) -> Void = { _, _, _ in }
      method_setImplementation(method, imp_implementationWithBlock(noop))
      matched = true
    }
    return matched
  }()
}

/// `XCTNSPredicateExpectation` re-evaluates on a one-second timer, so every wait built on it — and
/// that includes `waitForExistence` — costs a full second even when the condition was already true
/// before it was asked. A direct property read costs about seventy milliseconds, so polling one is
/// both faster to satisfy and faster to retry. An accessibility read blocks on the app's server
/// and paces the loop on its own, but a condition that reads nothing remote would spin a core, so
/// a failed check costs a short sleep before the next one.
func poll(timeout: TimeInterval = 3, until condition: () -> Bool) -> Bool {
  let deadline = Date().addingTimeInterval(timeout)
  repeat {
    if condition() {
      return true
    }
    usleep(10000)
  } while Date() < deadline
  return false
}

extension XCUIElement {
  @MainActor func awaitExistence(timeout: TimeInterval = 5) -> Bool {
    poll(timeout: timeout) { self.exists }
  }

  @MainActor func awaitNonExistence(timeout: TimeInterval = 3) -> Bool {
    poll(timeout: timeout) { !self.exists }
  }

  @MainActor func awaitHittable(timeout: TimeInterval = 3) -> Bool {
    poll(timeout: timeout) { self.isHittable }
  }

  /// `hasKeyboardFocus` is the attribute the old predicate waits queried, and it reaches XCUITest
  /// only through key-value coding — there is no Swift property for it.
  var hasKeyboardFocus: Bool {
    value(forKey: "hasKeyboardFocus") as? Bool ?? false
  }
}

extension XCUIApplication {
  /// Queried by identifier rather than element type: a multiline text entry surfaces as a text
  /// view or a text field depending on how it is built, and no assertion here is about which.
  @MainActor var tryItEditor: XCUIElement {
    descendants(matching: .any)["miniwhisper.onboarding.try-it.text"].firstMatch
  }
}

// MARK: - Surface

/// The app surfaces the suite is sliced by. A slice run (`mise run test:ui:<surface>`) sets
/// `MINIWHISPER_UI_SURFACES`, and every test class outside the requested surfaces skips.
enum Surface: String {
  case onboarding
  case menu
  case dictionary
  case history
  case settings
  case pill
}

// MARK: - SurfaceTagged

/// Every UI test class declares the surfaces it exercises — the tag lives with the tests it
/// describes. When one test's surfaces diverge from its class, that is the signal to split it
/// into its own class, not to widen the class's tags.
protocol SurfaceTagged {
  static var surfaces: Set<Surface> { get }
}

// MARK: - MiniWhisperUITestCase

/// Base class for every UI test. Swift cannot force a subclass to declare its surfaces at
/// compile time, so the next-loudest thing happens instead: every test of an untagged class
/// fails immediately, naming the fix.
class MiniWhisperUITestCase: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
    guard let tagged = type(of: self) as? SurfaceTagged.Type else {
      XCTFail("\(type(of: self)) declares no surfaces; conform to SurfaceTagged")
      throw SurfaceError.untaggedClass
    }
    guard let requestedRaw = ProcessInfo.processInfo.environment["MINIWHISPER_UI_SURFACES"],
          !requestedRaw.isEmpty
    else {
      return
    }
    let requested = try Set(requestedRaw.split(separator: ",").map { name -> Surface in
      guard let surface = Surface(rawValue: String(name)) else {
        XCTFail("Unknown surface \(name); see the Surface enum for the slice names")
        throw SurfaceError.unknownSurface
      }
      return surface
    })
    try XCTSkipUnless(
      !tagged.surfaces.isDisjoint(with: requested),
      "\(type(of: self)) covers \(tagged.surfaces), not \(requested)",
    )
  }
}

// MARK: - SurfaceError

private enum SurfaceError: Error {
  case untaggedClass
  case unknownSurface
}

// MARK: - Law

/// One claim about a launched scene. A group of them shares a single launch, because launching and
/// tearing down the app costs about two seconds and proving a law costs a fraction of that.
struct Law {
  // MARK: Lifecycle

  init(
    _ name: String, file: StaticString = #filePath, line: UInt = #line,
    _ body: @escaping @MainActor (XCUIApplication) throws -> Void,
  ) {
    self.name = name
    self.file = file
    self.line = line
    self.body = body
  }

  // MARK: Internal

  let name: String
  let file: StaticString
  let line: UInt
  let body: @MainActor (XCUIApplication) throws -> Void
}

// MARK: - UnmetRequirement

private struct UnmetRequirement: Error {}

/// The ground a law stands on. An ordinary assertion records a broken claim and lets the law finish
/// speaking; a broken requirement means the law was never asked the question it thought it was, so
/// it stops there rather than reporting on a window that is not the one it wanted.
func require(
  _ condition: @autoclosure () -> Bool, _ message: String = "Requirement unmet",
  file: StaticString = #filePath, line: UInt = #line,
) throws {
  guard condition() else {
    XCTFail(message, file: file, line: line)
    throw UnmetRequirement()
  }
}

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

  /// The menu scene persists dictionary edits to a real file; per test process so two runs on the
  /// same machine cannot read each other's words.
  var agentDictionaryFileURL: URL {
    FileManager.default.temporaryDirectory.appending(
      path: "miniwhisper-agent-dictionary-\(ProcessInfo.processInfo.processIdentifier).json",
    )
  }

  @MainActor func launch(
    _ scene: String, dictionaryData: Data? = nil, environment: [String: String] = [:],
  ) -> XCUIApplication {
    XCTAssertTrue(Quiescence.disabled, "XCTest renamed its quiescence hooks; update Quiescence")
    let app = XCUIApplication()
    parkPointer()
    try? FileManager.default.removeItem(at: agentCommandFileURL)
    try? FileManager.default.removeItem(at: agentResultFileURL)
    try? FileManager.default.removeItem(at: agentDictionaryFileURL)
    if let dictionaryData {
      do {
        try dictionaryData.write(to: agentDictionaryFileURL)
      } catch {
        XCTFail("Could not seed the agent dictionary: \(error)")
      }
    }
    app.launchEnvironment["MINIWHISPER_AGENT_SCENE"] = scene
    app.launchEnvironment.merge(environment) { _, requested in requested }
    app.launchEnvironment["MINIWHISPER_AGENT_COMMAND_FILE"] = agentCommandFileURL.path
    app.launchEnvironment["MINIWHISPER_AGENT_DICTIONARY_FILE"] = agentDictionaryFileURL.path
    app.launch()
    return app
  }

  /// One launch, many laws. Laws run in the order written and inherit the window the previous one
  /// left, so each opens by stating the ground it stands on.
  ///
  /// A broken claim is not a broken window: the law still made its gestures, so the laws behind it
  /// stand on the ground they expected and go on being asked. A broken requirement is different —
  /// the window was never the one the law thought it was addressing, and nothing after it can be
  /// read honestly, so the group stops there and names what it did not reach.
  @MainActor func assertLaws(
    on scene: String, _ laws: [Law], file: StaticString = #filePath, line: UInt = #line,
  ) {
    let app = launch(scene)
    defer { terminate(app) }
    continueAfterFailure = true
    defer { continueAfterFailure = false }

    for (index, law) in laws.enumerated() {
      let groundGaveWay = XCTContext.runActivity(named: law.name) { _ in
        do {
          try law.body(app)
        } catch is UnmetRequirement {
          // Already recorded at the requirement's own line.
          return true
        } catch {
          XCTFail("\(law.name): \(error)", file: law.file, line: law.line)
          return true
        }
        return false
      }
      if groundGaveWay {
        let unreached = laws[(index + 1)...].map(\.name)
        if !unreached.isEmpty {
          XCTFail(
            "\(law.name) did not find the window it expected, so these laws went unasked: "
              + unreached.joined(separator: ", "),
            file: file, line: line,
          )
        }
        return
      }
    }
  }

  @MainActor func terminate(_ app: XCUIApplication) {
    app.terminate()
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
  }

  @MainActor func clickImmediately(_ element: XCUIElement) {
    let point = CGPoint(x: element.frame.midX, y: element.frame.midY)
    CGWarpMouseCursorPosition(point)
    CGEvent(
      mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point,
      mouseButton: .left,
    )?.post(tap: .cghidEventTap)
    CGEvent(
      mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point,
      mouseButton: .left,
    )?.post(tap: .cghidEventTap)
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

  /// Swaps the running app to another state-presented scene — the same process, its state
  /// replaced — for the price of a poll cycle instead of a two-second relaunch. The result file
  /// is the barrier: consecutive scenes can answer to the same identifiers, so only the driver's
  /// confirmation distinguishes the new window from the stale one.
  func presentScene(_ scene: String) {
    postAgentMutation("scene", value: scene)
    waitForAgentResult("scene:\(scene)")
  }

  func postAgentMutation(_ action: String, value: Any) {
    try! "\(UUID().uuidString)|\(action)|\(value)".write(
      to: agentCommandFileURL, atomically: true, encoding: .utf8,
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

  /// `XCTestCase` is an `NSObject`, so both overloads would claim the `accessibilityValue:`
  /// selector; the snapshot one is Swift-only and gives the name up.
  @nonobjc @MainActor func accessibilityValue(_ snapshot: XCUIElementSnapshot) -> String {
    snapshot.value.map { String(describing: $0) } ?? ""
  }

  @MainActor func accessibilitySnapshots(
    _ root: XCUIElementSnapshot,
  ) -> [String: [XCUIElementSnapshot]] {
    var snapshots: [String: [XCUIElementSnapshot]] = [:]
    func walk(_ snapshot: XCUIElementSnapshot) {
      if snapshot.identifier.hasPrefix("miniwhisper.") {
        snapshots[snapshot.identifier, default: []].append(snapshot)
      }
      snapshot.children.forEach(walk)
    }
    walk(root)
    return snapshots
  }

  func assertValue(
    _ expectedValue: String, of element: XCUIElement, file: StaticString = #filePath,
    line: UInt = #line,
  ) {
    XCTAssertTrue(
      poll(until: { self.accessibilityValue(element) == expectedValue }),
      "\(element.identifier) is \(accessibilityValue(element)), not \(expectedValue)",
      file: file, line: line,
    )
  }

  func assertLabel(
    _ expectedLabel: String, of element: XCUIElement, file: StaticString = #filePath,
    line: UInt = #line,
  ) {
    XCTAssertTrue(
      poll(until: { element.label == expectedLabel }),
      "\(element.identifier) is labeled \(element.label), not \(expectedLabel)",
      file: file, line: line,
    )
  }

  /// Whether a control can be pressed. Existence has `awaitExistence`; this is the other property
  /// an interaction changes asynchronously, and reading it bare is the same race.
  func assertEnabled(
    _ isEnabled: Bool, of element: XCUIElement, _ message: String,
    file: StaticString = #filePath, line: UInt = #line,
  ) {
    XCTAssertTrue(
      poll(until: { element.isEnabled == isEnabled }), message, file: file, line: line,
    )
  }

  func assertKeyboardFocus(
    on element: XCUIElement, file: StaticString = #filePath, line: UInt = #line,
  ) {
    XCTAssertTrue(
      poll(until: { element.hasKeyboardFocus }),
      "\(element.identifier) does not have keyboard focus", file: file, line: line,
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
