import AppKit
import ApplicationServices
import XCTest

/// UI tests only ever drive the Debug product, which keeps its own bundle identifier so that its
/// permission grants never collide with an installed release build.
private let debugBundleIdentifier = "com.thurstonsand.MiniWhisper.dev"

// MARK: - MiniWhisperUITests

final class MiniWhisperUITests: XCTestCase {
  // MARK: Internal

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor func testOnboardingAccessibilityManifest() throws {
    try assertManifest(
      scene: "onboarding-welcome",
      elements: [
        contract(.window, "miniwhisper.onboarding.window", "Set Up MiniWhisper"),
        contract(.group, "miniwhisper.onboarding.welcome", "Welcome to MiniWhisper"),
        contract(
          .staticText, "miniwhisper.onboarding.welcome.title", "Application name", "MiniWhisper",
        ),
        contract(
          .staticText, "miniwhisper.onboarding.welcome.summary", "Welcome summary",
          "Fast, accurate dictation that runs on your Mac.",
        ),
        contract(
          .staticText, "miniwhisper.onboarding.welcome.model-info", "Model download information",
          "Download the speech model in the background while you finish setup.",
        ),
        contract(
          .button, "miniwhisper.onboarding.download-model", "Download Parakeet v2", isEnabled: true,
          isActionable: true,
        ),
      ],
    )

    for permission in PermissionManifest.allCases {
      try assertManifest(
        scene: permission.scene,
        elements: onboardingRail(permission.railValues) + permissionElements(permission),
      )
    }

    try assertManifest(
      scene: "onboarding-model",
      elements: onboardingRail(["Complete", "Current; Downloading 42%", "Available"]) + [
        contract(.group, "miniwhisper.onboarding.model", "Speech model setup"),
        contract(
          .staticText, "miniwhisper.onboarding.model.title", "Model setup heading",
          "Prepare Parakeet v2",
        ),
        contract(
          .staticText, "miniwhisper.onboarding.model.summary", "Model setup information",
          "Downloads once (~450 MB), then everything runs on this Mac.",
        ),
        contract(
          .staticText, "miniwhisper.onboarding.model.status", "Model status", "Downloading model",
        ),
        contract(
          .progressIndicator, "miniwhisper.onboarding.model-progress", "Model download", "0.42",
        ),
      ],
    )

    try assertManifest(
      scene: "onboarding-try-it",
      elements: onboardingRail(["Complete", "Complete", "Current"]) + [
        contract(.group, "miniwhisper.onboarding.try-it", "Try MiniWhisper"),
        contract(
          .staticText, "miniwhisper.onboarding.try-it.title", "Try it heading", "Give it a try",
        ),
        contract(
          .staticText, "miniwhisper.onboarding.try-it.instructions", "Try it instructions",
          "Focus the text box below, hold Right Option while you speak, then release. Or double-tap Right Option to keep recording until you tap it again.",
        ), contract(.textView, "miniwhisper.onboarding.try-it.text", "Try dictation", ""),
        contract(
          .staticText, "miniwhisper.onboarding.try-it.hotkey", "Dictation hotkey", "Right Option",
        ),
        contract(
          .staticText, "miniwhisper.onboarding.try-it.guidance", "Try it guidance",
          "Speak to complete…",
        ),
        contract(
          .button, "miniwhisper.onboarding.try-it.skip", "Skip test dictation", isEnabled: true,
          isActionable: true,
        ),
      ],
    )

    try assertManifest(
      scene: "onboarding-ready",
      elements: onboardingRail(["Complete", "Complete", "Complete"]) + [
        contract(.group, "miniwhisper.onboarding.ready", "MiniWhisper is ready"),
        contract(.staticText, "miniwhisper.onboarding.ready.title", "Setup status", "Ready"),
        contract(
          .staticText, "miniwhisper.onboarding.ready.summary", "Ready instructions",
          "Your first dictation made the full trip. Hold Right Option in any text field and speak.",
        ),
        contract(
          .staticText, "miniwhisper.onboarding.ready.transcript", "Completed dictation",
          "MiniWhisper is ready.",
        ),
        contract(
          .button, "miniwhisper.onboarding.ready.finish", "Start Dictating", isEnabled: true,
          isActionable: true,
        ),
      ],
    )
  }

  @MainActor func testMenuAccessibilityManifest() throws {
    try assertMenuManifest(
      scene: "menu-healthy",
      elements: [
        contract(
          .menuItem, "miniwhisper.menu.status", "Status", "Ready; Parakeet v2; Test Microphone",
          isEnabled: false,
        ),
        contract(
          .menuItem, "miniwhisper.menu.copy-last-transcript", "Copy Last Transcript",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .menuItem, "miniwhisper.menu.sounds", "Sounds", "On", isEnabled: true,
          isActionable: true,
        ),
        contract(
          .menuItem, "miniwhisper.menu.launch-at-login", "Launch at Login", "On", isEnabled: true,
          isActionable: true,
        ),
        contract(
          .menuItem, "miniwhisper.menu.settings-file", "Open Settings File", isEnabled: true,
          isActionable: true,
        ),
        contract(
          .menuItem, "miniwhisper.menu.about", "About MiniWhisper", isEnabled: true,
          isActionable: true,
        ),
        contract(
          .menuItem, "miniwhisper.menu.quit", "Quit MiniWhisper", isEnabled: true,
          isActionable: true,
        ),
      ],
    )

    try assertMenuManifest(
      scene: "menu-degraded",
      elements: [
        contract(
          .menuItem, "miniwhisper.menu.status", "Status",
          "Accessibility is off, so the hotkey and pasting can't work; switch it on",
          isEnabled: false,
        ),
        contract(
          .menuItem, "miniwhisper.menu.repair", "Open Accessibility Settings…", isEnabled: true,
          isActionable: true,
        ),
        contract(
          .menuItem, "miniwhisper.menu.copy-last-transcript", "Copy Last Transcript",
          isEnabled: false,
        ),
        contract(
          .menuItem, "miniwhisper.menu.sounds", "Sounds", "Off", isEnabled: true,
          isActionable: true,
        ),
        contract(
          .menuItem, "miniwhisper.menu.launch-at-login", "Launch at Login", "Off", isEnabled: true,
          isActionable: true,
        ),
        contract(
          .menuItem, "miniwhisper.menu.settings-file", "Open Settings File", isEnabled: true,
          isActionable: true,
        ),
        contract(
          .menuItem, "miniwhisper.menu.about", "About MiniWhisper", isEnabled: true,
          isActionable: true,
        ),
        contract(
          .menuItem, "miniwhisper.menu.quit", "Quit MiniWhisper", isEnabled: true,
          isActionable: true,
        ),
      ],
    )
  }

  @MainActor func testAboutAccessibilityManifest() throws {
    try assertManifest(
      scene: "about",
      elements: [
        contract(.window, "miniwhisper.about.window", "About MiniWhisper"),
        contract(.group, "miniwhisper.about.content", "About MiniWhisper"),
        contract(.image, "miniwhisper.about.icon", "MiniWhisper icon"),
        contract(.staticText, "miniwhisper.about.app-name", "Application", "MiniWhisper"),
        contract(
          .staticText, "miniwhisper.about.version", "Version",
          valuePattern: #"^Version [0-9]+\.[0-9]+(?:\.[0-9]+)? \([0-9]+\)$"#,
        ),
        contract(
          .staticText, "miniwhisper.about.attribution", "Speech recognition attribution",
          "NVIDIA Parakeet TDT 0.6B v2, licensed under CC BY 4.0",
        ),
        contract(
          .link, "miniwhisper.about.model-link", "Open the Parakeet TDT 0.6B v2 model page",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .staticText, "miniwhisper.about.fluid-audio-attribution", "FluidAudio attribution",
          "FluidAudio, licensed under the Apache License 2.0",
        ),
        contract(
          .link, "miniwhisper.about.fluid-audio-link", "Open the FluidAudio project page",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .button, "miniwhisper.about.close", "Close About MiniWhisper", isEnabled: true,
          isActionable: true,
        ),
      ],
    )
  }

  @MainActor func testPillAccessibilityManifest() throws {
    try assertManifest(
      scene: "pill-recording",
      elements: [
        contract(.dialog, "miniwhisper.pill", "MiniWhisper dictation", "Visible"),
        contract(.staticText, "miniwhisper.pill.phase", "Dictation phase", "Recording"),
        contract(.staticText, "miniwhisper.pill.capture-status", "Capture status", "Live"),
        contract(.staticText, "miniwhisper.pill.input-device", "Input device", "Test Microphone"),
        contract(.staticText, "miniwhisper.pill.audio-level", "Input level", "70%"),
      ],
      mutation: { app in
        let level = app.descendants(matching: .any)["miniwhisper.pill.audio-level"]
        self.postAgentMutation("pill-level", value: 0.23)
        self.assertValue("20%", of: level)
      },
    )
    try assertManifest(
      scene: "pill-transcribing",
      elements: [
        contract(.dialog, "miniwhisper.pill", "MiniWhisper dictation", "Visible"),
        contract(.staticText, "miniwhisper.pill.phase", "Dictation phase", "Transcribing"),
      ],
    )
    try assertManifest(
      scene: "pill-no-speech",
      elements: [
        contract(.dialog, "miniwhisper.pill", "MiniWhisper dictation", "Visible"),
        contract(.staticText, "miniwhisper.pill.phase", "Dictation phase", "No speech detected"),
        contract(.staticText, "miniwhisper.pill.notice", "Dictation notice", "No speech detected"),
      ],
    )
    try assertManifest(
      scene: "pill-copied",
      elements: [
        contract(.dialog, "miniwhisper.pill", "MiniWhisper dictation", "Visible"),
        contract(.staticText, "miniwhisper.pill.phase", "Dictation phase", "Copied"),
        contract(
          .staticText, "miniwhisper.pill.notice", "Dictation notice", "Copied — ⌘V to paste",
        ),
      ],
    )
  }

  @MainActor func testRawAccessibilityAccessFromUITestRunner() throws {
    let app = launch("pill-recording")
    defer { terminate(app) }
    let xcuPhase = app.descendants(matching: .any)["miniwhisper.pill.phase"]
    XCTAssertTrue(xcuPhase.waitForExistence(timeout: 5))

    let application = try XCTUnwrap(
      NSRunningApplication.runningApplications(withBundleIdentifier: debugBundleIdentifier).first {
        $0.bundleURL?.path.contains("/.build/DerivedData/") == true
      },
    )
    let isTrusted = AXIsProcessTrusted()
    let result = RawAccessibilityProbe().read(
      applicationPID: application.processIdentifier, identifier: "miniwhisper.pill.phase",
    )

    switch result {
    case let .snapshot(snapshot):
      XCTAssertEqual(snapshot.role, "AXStaticText")
      XCTAssertEqual(snapshot.identifier, xcuPhase.identifier)
      XCTAssertEqual(snapshot.label, xcuPhase.label)
      XCTAssertEqual(snapshot.value, accessibilityValue(xcuPhase))
      recordSpikeEvidence(
        "Raw AX succeeded; runner trusted=\(isTrusted); identifier=\(snapshot.identifier); label=\(snapshot.label); value=\(snapshot.value)",
      )
    case let .failure(failure):
      XCTAssertFalse(isTrusted, "Raw AX failed even though the UI-test runner is trusted")
      XCTAssertTrue(
        failure.error == .apiDisabled || failure.error == .cannotComplete,
        "Unexpected raw AX failure: \(failure.error.rawValue) reading \(failure.attribute)",
      )
      recordSpikeEvidence(
        "Raw AX requires Accessibility trust; runner trusted=false; error=\(failure.error.rawValue); attribute=\(failure.attribute). XCUITest read identifier=\(xcuPhase.identifier), label=\(xcuPhase.label), value=\(accessibilityValue(xcuPhase)).",
      )
    case .notFound:
      XCTFail("Raw AX access succeeded, but the pill phase identifier was absent")
    }
  }

  @MainActor func testAccessibilityAudit() throws {
    for scene in ["onboarding-welcome", "about"] {
      try assertAccessibilityAudit(scene: scene)
    }
  }

  @MainActor func testLaunchPerformance() throws {
    throw XCTSkip("Launch performance metrics are unstable for the menu bar test host.")
  }

  // MARK: Private

  private var agentCommandFileURL: URL {
    FileManager.default.temporaryDirectory.appending(
      path: "miniwhisper-agent-driveability-\(ProcessInfo.processInfo.processIdentifier)",
    )
  }

  @MainActor private func assertAccessibilityAudit(scene: String) throws {
    let app = launch(scene)
    defer { terminate(app) }
    XCTAssertTrue(
      app.descendants(matching: .any)
        .matching(
          NSPredicate(format: "identifier BEGINSWITH %@", "miniwhisper."),
        )
        .firstMatch
        .waitForExistence(timeout: 5),
    )
    try app.performAccessibilityAudit(for: [.elementDetection, .action])
  }

  @MainActor private func assertMenuManifest(
    scene: String, elements: [AccessibilityContract], file: StaticString = #filePath,
    line: UInt = #line,
  ) throws {
    let app = launch(scene)
    defer { terminate(app) }
    let statusItem = app.statusItems["miniwhisper.menu.status-item"]
    XCTAssertTrue(statusItem.waitForExistence(timeout: 5), file: file, line: line)
    XCTAssertEqual(statusItem.label, "MiniWhisper", file: file, line: line)
    XCTAssertTrue(statusItem.isEnabled, file: file, line: line)
    XCTAssertTrue(
      statusItem.isHittable, "Status item is hidden by menu bar overflow.", file: file, line: line,
    )
    statusItem.click()
    XCTAssertTrue(
      app.menuItems[elements[0].identifier].waitForExistence(timeout: 2), file: file, line: line,
    )
    assert(elements, in: app, file: file, line: line)
    if scene == "menu-healthy" {
      postAgentMutation("sounds", value: false)
      assertValue("Off", of: app.menuItems["miniwhisper.menu.sounds"])
      postAgentMutation("launch-at-login", value: false)
      assertValue("Off", of: app.menuItems["miniwhisper.menu.launch-at-login"])
    }
  }

  @MainActor private func assertManifest(
    scene: String, elements: [AccessibilityContract], mutation: ((XCUIApplication) -> Void)? = nil,
    file: StaticString = #filePath, line: UInt = #line,
  ) throws {
    let app = launch(scene)
    defer { terminate(app) }
    XCTAssertTrue(
      app.descendants(matching: .any)[elements[0].identifier].waitForExistence(timeout: 5),
      file: file, line: line,
    )
    assert(elements, in: app, allowing: menuKnownIdentifiers, file: file, line: line)
    mutation?(app)
  }

  @MainActor private func launch(_ scene: String) -> XCUIApplication {
    let app = XCUIApplication()
    try? FileManager.default.removeItem(at: agentCommandFileURL)
    app.launchEnvironment["MINIWHISPER_AGENT_SCENE"] = scene
    app.launchEnvironment["MINIWHISPER_AGENT_COMMAND_FILE"] = agentCommandFileURL.path
    app.launch()
    return app
  }

  private func postAgentMutation(_ action: String, value: Any) {
    try! "\(UUID().uuidString)|\(action)|\(value)".write(
      to: agentCommandFileURL, atomically: true, encoding: .utf8,
    )
  }

  private func assertValue(
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

  private func recordSpikeEvidence(_ evidence: String) {
    print("RAW_AX_SPIKE: \(evidence)")
    let attachment = XCTAttachment(string: evidence)
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  @MainActor private func terminate(_ app: XCUIApplication) {
    app.terminate()
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
  }

  @MainActor private func assert(
    _ contracts: [AccessibilityContract], in app: XCUIApplication,
    allowing extraIdentifiers: Set<String> = [], file: StaticString, line: UInt,
  ) {
    let expectedIdentifiers = Set(contracts.map(\.identifier))
    for contract in contracts {
      let matches = app.descendants(matching: .any)
        .matching(identifier: contract.identifier)
        .allElementsBoundByIndex
      XCTAssertEqual(
        matches.count, 1, "Expected one \(contract.identifier)", file: file, line: line,
      )
      guard let element = matches.first else {
        continue
      }
      XCTAssertEqual(
        element.elementType, contract.elementType, contract.identifier, file: file, line: line,
      )
      XCTAssertFalse(
        element.label.isEmpty, "\(contract.identifier) has no label", file: file, line: line,
      )
      XCTAssertEqual(element.label, contract.label, contract.identifier, file: file, line: line)
      if let value = contract.value {
        if accessibilityValue(element) != value {
          let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value), object: element,
          )
          _ = XCTWaiter.wait(for: [expectation], timeout: 2)
        }
        XCTAssertEqual(
          accessibilityValue(element), value, contract.identifier, file: file, line: line,
        )
      }
      if let valuePattern = contract.valuePattern {
        XCTAssertNotNil(
          accessibilityValue(element).range(of: valuePattern, options: .regularExpression),
          contract.identifier, file: file, line: line,
        )
      }
      if let isEnabled = contract.isEnabled {
        XCTAssertEqual(element.isEnabled, isEnabled, contract.identifier, file: file, line: line)
      }
      if contract.isActionable {
        XCTAssertTrue(element.isEnabled, contract.identifier, file: file, line: line)
        XCTAssertTrue(element.isHittable, contract.identifier, file: file, line: line)
      }
    }

    let namespacedElements = app.descendants(matching: .any)
      .matching(
        NSPredicate(format: "identifier BEGINSWITH %@", "miniwhisper."),
      )
      .allElementsBoundByIndex
    let identifiers = namespacedElements.map(\.identifier)
    let duplicateIdentifiers = Dictionary(grouping: identifiers, by: { $0 }).filter {
      $0.value.count > 1
    }
    XCTAssertTrue(
      duplicateIdentifiers.isEmpty, "Duplicate identifiers: \(duplicateIdentifiers.keys.sorted())",
      file: file, line: line,
    )

    let allowedIdentifiers = expectedIdentifiers.union(extraIdentifiers).union([
      "miniwhisper.menu.status-item",
    ])
    let unexpectedIdentifiers = Set(identifiers).subtracting(allowedIdentifiers)
    XCTAssertTrue(
      unexpectedIdentifiers.isEmpty, "Unexpected identifiers: \(unexpectedIdentifiers.sorted())",
      file: file, line: line,
    )
  }

  private func accessibilityValue(_ element: XCUIElement) -> String {
    guard let value = element.value else {
      return ""
    }
    return String(describing: value)
  }

  private func contract(
    _ elementType: XCUIElement.ElementType, _ identifier: String, _ label: String,
    _ value: String? = nil, valuePattern: String? = nil, isEnabled: Bool? = nil,
    isActionable: Bool = false,
  ) -> AccessibilityContract {
    AccessibilityContract(
      elementType: elementType, identifier: identifier, label: label, value: value,
      valuePattern: valuePattern, isEnabled: isEnabled, isActionable: isActionable,
    )
  }

  private func onboardingRail(_ values: [String]) -> [AccessibilityContract] {
    [
      contract(.window, "miniwhisper.onboarding.window", "Set Up MiniWhisper"),
      contract(.group, "miniwhisper.onboarding.rail", "Setup steps"),
      contract(.staticText, "miniwhisper.onboarding.rail.brand", "Application name", "MiniWhisper"),
      contract(
        .staticText, "miniwhisper.onboarding.rail.tagline", "Application description",
        "fast and accurate dictation",
      ),
      contract(
        .button, "miniwhisper.onboarding.rail.permissions", "Permissions", values[0],
        isEnabled: true, isActionable: true,
      ),
      contract(
        .button, "miniwhisper.onboarding.rail.model", "Speech Model", values[1], isEnabled: true,
        isActionable: true,
      ),
      contract(
        .button, "miniwhisper.onboarding.rail.try-it", "Try It", values[2], isEnabled: true,
        isActionable: true,
      ),
    ]
  }

  private func permissionElements(_ manifest: PermissionManifest) -> [AccessibilityContract] {
    let action = manifest.action
    let statuses = manifest.statuses
    var elements = [
      contract(.group, "miniwhisper.onboarding.permissions", "Permissions setup"),
      contract(
        .staticText, "miniwhisper.onboarding.permissions.title", "Permissions heading",
        "We need access to a few things first",
      ),
      contract(
        .staticText, "miniwhisper.onboarding.permissions.summary", "Permissions information",
        "macOS prompts for both. Grant them in the order they appear.",
      ),
      contract(
        .staticText, "miniwhisper.onboarding.permission.microphone", "Microphone",
        "Hear your beautiful voice",
      ),
      contract(
        .staticText, "miniwhisper.onboarding.permission.microphone.status", "Microphone status",
        statuses[0],
      ),
      contract(
        .staticText, "miniwhisper.onboarding.permission.accessibility", "Accessibility",
        "Watch for the dictation hotkey, paste at your cursor, and read the text around it.",
      ),
      contract(
        .staticText, "miniwhisper.onboarding.permission.accessibility.status",
        "Accessibility status", statuses[1],
      ),
      contract(
        .staticText, "miniwhisper.onboarding.permissions.guidance", "Permissions guidance",
        manifest.guidance,
      ),
    ]
    elements.append(
      contract(.button, action.identifier, action.label, isEnabled: true, isActionable: true),
    )
    return elements
  }
}

// MARK: - AccessibilityContract

private struct AccessibilityContract {
  let elementType: XCUIElement.ElementType
  let identifier: String
  let label: String
  let value: String?
  let valuePattern: String?
  let isEnabled: Bool?
  let isActionable: Bool
}

// MARK: - PermissionAction

private enum PermissionAction {
  case microphone
  case accessibility

  // MARK: Internal

  var identifier: String {
    switch self {
    case .microphone:
      "miniwhisper.onboarding.permission.microphone.action"
    case .accessibility:
      "miniwhisper.onboarding.permission.accessibility.action"
    }
  }

  var label: String {
    switch self {
    case .microphone:
      "Grant Microphone"
    case .accessibility:
      "Grant Accessibility"
    }
  }
}

// MARK: - PermissionManifest

private enum PermissionManifest: CaseIterable {
  case microphone
  case accessibility

  // MARK: Internal

  var scene: String {
    switch self {
    case .microphone:
      "onboarding-permissions-microphone"
    case .accessibility:
      "onboarding-permissions-accessibility"
    }
  }

  var action: PermissionAction {
    switch self {
    case .microphone:
      .microphone
    case .accessibility:
      .accessibility
    }
  }

  var statuses: [String] {
    switch self {
    case .microphone:
      ["Required", "Required"]
    case .accessibility:
      ["Granted", "Required"]
    }
  }

  var guidance: String {
    "Continue after granting both"
  }

  var railValues: [String] {
    ["Current", "Available; Downloading 42%", "Available"]
  }
}

private let menuKnownIdentifiers: Set<String> = [
  "miniwhisper.menu.status", "miniwhisper.menu.repair", "miniwhisper.menu.copy-last-transcript",
  "miniwhisper.menu.sounds", "miniwhisper.menu.launch-at-login", "miniwhisper.menu.settings-file",
  "miniwhisper.menu.about", "miniwhisper.menu.quit",
]
