import AppKit
import ApplicationServices
import Foundation
import OSLog

// MARK: - ChromiumAccessibility

/// Chromium builds its accessibility tree lazily. Electron apps wake on the documented
/// `AXManualAccessibility` write; Chrome 151 rejects both documented attributes, and only a tree
/// traversal (~135 ms on first walk) wakes it. That walk happens here — at recording start, once
/// per running instance — because delivery cannot afford it. A dictation that beats the walk
/// simply reports its context unavailable.
enum ChromiumAccessibility {
  // MARK: Internal

  static func prewarmFrontmostApp() async {
    guard AXIsProcessTrusted() else {
      return
    }
    guard let frontmost = NSWorkspace.shared.frontmostApplication,
          let family = family(of: frontmost.bundleURL)
    else {
      return
    }

    // PIDs are recycled, so an instance is its PID and the moment it started.
    let instance = WakeLedger.Instance(
      pid: frontmost.processIdentifier, launchedAt: frontmost.launchDate,
    )
    let bundleID = frontmost.bundleIdentifier ?? "?"
    guard await ledger.claim(instance) else {
      return
    }

    let woken = await wake(pid: instance.pid, family: family, bundleID: bundleID)
    // A wake that did not take is worth trying again at the next recording start; only a working
    // tree earns the right to skip the walk.
    await ledger.settle(instance, woken: woken)
  }

  // MARK: Private

  private enum Family {
    case electron
    case chromiumBrowser
  }

  private static let wakeMessagingTimeout: Float = 1
  private static let settleBeforeTraversal = Duration.milliseconds(500)
  private static let maximumVisitedNodes = 5000
  private static let ledger = WakeLedger()

  private static func wake(pid: pid_t, family: Family, bundleID: String) async -> Bool {
    let application = AXUIElementCreateApplication(pid)
    guard AXUIElementSetMessagingTimeout(application, wakeMessagingTimeout) == .success else {
      return false
    }

    let result = AXUIElementSetAttributeValue(
      application, "AXManualAccessibility" as CFString, kCFBooleanTrue,
    )
    contextLogger.info(
      "Chromium wake bundle=\(bundleID, privacy: .public) manualAccessibility=\(result.rawValue)",
    )
    guard family == .chromiumBrowser else {
      return result == .success
    }

    do { try await Task.sleep(for: settleBeforeTraversal) } catch { return false }
    if case .success = AXRead.element(application, kAXFocusedUIElementAttribute) {
      return true
    }

    let clock = ContinuousClock()
    let started = clock.now
    let visited = traverse(application)
    let duration = started.duration(to: clock.now).components
    let elapsed = Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
    contextLogger.info(
      "Chromium wake bundle=\(bundleID, privacy: .public) traversal nodes=\(visited) elapsed=\(elapsed, format: .fixed(precision: 1))ms",
    )
    return visited > 1
  }

  private static func traverse(_ application: AXUIElement) -> Int {
    var pending = [application]
    var next = 0
    var visited = 0
    while next < pending.count, visited < maximumVisitedNodes, !Task.isCancelled {
      let element = pending[next]
      next += 1
      guard AXUIElementSetMessagingTimeout(element, wakeMessagingTimeout) == .success else {
        continue
      }
      visited += 1
      _ = AXRead.value(element, kAXRoleAttribute)
      if case let .success(children) = AXRead.children(element) {
        pending.append(contentsOf: children)
      }
    }
    return visited
  }

  /// Every Chromium build ships a renderer helper beside its content framework, so that helper is
  /// the family's signature. Framework *names* are not: Chrome embeds `Google Chrome
  /// Framework.framework`, but Dia hides the same Chromium inside `ArcCore.framework`, and a name
  /// test walked straight past it. Reading the bundle still beats a bundle-ID allowlist.
  private static func family(of bundleURL: URL?) -> Family? {
    guard let bundleURL else {
      return nil
    }
    let frameworksDirectory = bundleURL.appending(path: "Contents/Frameworks")
    let frameworks = contents(of: frameworksDirectory)
    guard !frameworks.isEmpty else {
      return nil
    }
    if frameworks.contains("Electron Framework.framework") {
      return .electron
    }

    // Chrome: <name> Framework.framework/Versions/<version>/Helpers/<name> Helper (Renderer).app
    // Dia:    ArcCore.framework/Versions/A/Helpers/Browser Helper (Renderer).app
    for framework in frameworks where framework.hasSuffix(".framework") {
      let versions = frameworksDirectory.appending(path: "\(framework)/Versions")
      for version in contents(of: versions) {
        let helpers = contents(of: versions.appending(path: "\(version)/Helpers"))
        if helpers.contains(where: { $0.hasSuffix(" (Renderer).app") }) {
          return .chromiumBrowser
        }
      }
    }
    return nil
  }

  private static func contents(of directory: URL) -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
  }
}

// MARK: - WakeLedger

private actor WakeLedger {
  // MARK: Internal

  struct Instance: Hashable {
    var pid: pid_t
    var launchedAt: Date?
  }

  func claim(_ instance: Instance) -> Bool {
    guard !woken.contains(instance) else {
      return false
    }
    return inProgress.insert(instance).inserted
  }

  func settle(_ instance: Instance, woken didWake: Bool) {
    inProgress.remove(instance)
    if didWake {
      woken.insert(instance)
    }
  }

  // MARK: Private

  private var inProgress = Set<Instance>()
  private var woken = Set<Instance>()
}
