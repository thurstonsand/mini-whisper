import AppKit
import XCTest

// MARK: - MiniWhisperUITests

final class MiniWhisperUITests: XCTestCase {
  // MARK: Internal

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor func testOnboardingAccessibilityManifest() throws {
    let app = launch("onboarding-welcome")
    defer { terminate(app) }
    try assertManifest(
      in: app,
      audits: true,
      elements: [
        contract(.window, "miniwhisper.onboarding.window", "Set Up \(appName)"),
        contract(.group, "miniwhisper.onboarding.welcome", "Welcome to \(appName)"),
        contract(
          .staticText, "miniwhisper.onboarding.welcome.title", "Application name", appName,
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
      presentScene(permission.scene)
      try assertManifest(
        in: app,
        elements: onboardingRail(permission.railValues) + permissionElements(permission),
      )
    }

    presentScene("onboarding-shortcut")
    try assertManifest(
      in: app,
      elements: onboardingRail(
        ["Complete", "Current", "Available; Downloading 42%", "Available"],
      ) + [
        contract(.group, "miniwhisper.onboarding.shortcut", "Activation shortcut setup"),
        contract(
          .staticText, "miniwhisper.onboarding.shortcut.title", "Shortcut heading",
          "Activating \(appName)",
        ),
        contract(
          .staticText, "miniwhisper.onboarding.shortcut.summary", "Shortcut information",
          "Shortcut to start dictation.",
        ),
        contract(
          .button, "miniwhisper.onboarding.shortcut.binding", "Dictation shortcut", "⌥ Opt →",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .staticText, "miniwhisper.onboarding.shortcut.binding.state",
          "Dictation shortcut ring", "Ring off",
        ),
        contract(
          .staticText, "miniwhisper.onboarding.shortcut.caption", "Shortcut guidance",
          "Click the shortcut to change",
        ),
        contract(
          .button, "miniwhisper.onboarding.shortcut.continue", "Continue", isEnabled: true,
          isActionable: true,
        ),
      ],
    )

    presentScene("onboarding-model")
    try assertManifest(
      in: app,
      elements: onboardingRail(["Complete", "Complete", "Current; Downloading 42%", "Available"]) +
        [
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

    presentScene("onboarding-try-it")
    try assertManifest(
      in: app,
      elements: onboardingRail(["Complete", "Complete", "Complete", "Current"]) + [
        contract(.group, "miniwhisper.onboarding.try-it", "Try \(appName)"),
        contract(
          .staticText, "miniwhisper.onboarding.try-it.title", "Try it heading", "Give it a try",
        ),
        contract(
          .staticText, "miniwhisper.onboarding.try-it.instructions", "Try it instructions",
          "Focus the text box below, hold ⌥ Opt → while you speak, then release. Or double-tap ⌥ Opt → to keep recording until you tap it again.",
        ), contract(.textView, "miniwhisper.onboarding.try-it.text", "Try dictation", ""),
        contract(
          .staticText, "miniwhisper.onboarding.try-it.hotkey", "Dictation hotkey", "⌥ Opt →",
        ),
        contract(
          .staticText, "miniwhisper.onboarding.try-it.guidance", "Try it guidance",
          "Speak to complete…",
        ),
        contract(
          .button, "miniwhisper.onboarding.try-it.skip", "Skip test dictation", isEnabled: true,
          isActionable: true,
        ),
        contract(
          .staticText, "miniwhisper.onboarding.try-it.skip.state", "Skip ring", "Ring off",
        ),
      ],
    )

    presentScene("onboarding-ready")
    try assertManifest(
      in: app,
      elements: onboardingRail(["Complete", "Complete", "Complete", "Complete"]) + [
        contract(.group, "miniwhisper.onboarding.ready", "\(appName) is ready"),
        contract(.staticText, "miniwhisper.onboarding.ready.title", "Setup status", "Ready"),
        contract(
          .staticText, "miniwhisper.onboarding.ready.summary", "Ready instructions",
          "Your first dictation made the full trip. Hold ⌥ Opt → in any text field and speak.",
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
          .menuItem, "miniwhisper.menu.settings", "Settings", isEnabled: true,
          isActionable: true,
        ),
        contract(
          .menuItem, "miniwhisper.menu.about", "About \(appName)", isEnabled: true,
          isActionable: true,
        ),
        contract(
          .menuItem, "miniwhisper.menu.quit", "Quit \(appName)", isEnabled: true,
          isActionable: true,
        ),
      ],
    )

    try assertMenuManifest(
      scene: "menu-degraded",
      elements: [
        contract(
          .menuItem, "miniwhisper.menu.status", "Status",
          "Not ready; Test Microphone", isEnabled: false,
        ),
        contract(
          .menuItem, "miniwhisper.menu.repair.accessibility", "Grant Accessibility Access…",
          "Required to start dictation and paste text",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .menuItem, "miniwhisper.menu.repair.microphone", "Grant Microphone Access…",
          "Required to record audio",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .menuItem, "miniwhisper.menu.copy-last-transcript", "Copy Last Transcript",
          isEnabled: false,
        ),
        contract(
          .menuItem, "miniwhisper.menu.settings", "Settings", isEnabled: true,
          isActionable: true,
        ),
        contract(
          .menuItem, "miniwhisper.menu.about", "About \(appName)", isEnabled: true,
          isActionable: true,
        ),
        contract(
          .menuItem, "miniwhisper.menu.quit", "Quit \(appName)", isEnabled: true,
          isActionable: true,
        ),
      ],
    )
  }

  @MainActor func testSettingsAccessibilityManifest() throws {
    try assertManifest(
      scene: "settings",
      elements: [
        contract(.window, "miniwhisper.settings.window", "\(appName) Settings"),
        contract(.outline, "miniwhisper.settings.sidebar", "Settings sections", "Focused"),
        contract(
          .staticText, "miniwhisper.settings.sidebar.settings", "Settings section",
          "Settings; Selected",
        ),
        contract(
          .staticText, "miniwhisper.settings.sidebar.history", "History section",
          "History; Not selected",
        ),
        contract(
          .staticText, "miniwhisper.settings.sidebar.model", "Model section",
          "Model; Not selected",
        ),
        contract(
          .staticText, "miniwhisper.settings.sidebar.dictionary", "Dictionary section",
          "Dictionary; Not selected",
        ),
        contract(
          .staticText, "miniwhisper.settings.sidebar.cleanup", "Cleanup section",
          "Cleanup; Not selected",
        ),
        contract(.group, "miniwhisper.settings.shortcut.activate", "Activate shortcut"),
        contract(
          .staticText, "miniwhisper.settings.shortcut.activate.state",
          "Activate shortcut highlight", "Bar off",
        ),
        contract(
          .button, "miniwhisper.settings.shortcut.binding.0", "⌥ Opt →", "Ring off",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .button, "miniwhisper.settings.shortcut.binding.1", "⌃ Ctrl → R", "Ring off",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .menuButton, "miniwhisper.settings.shortcut.menu", "Shortcut actions", isEnabled: true,
          isActionable: true,
        ),
        contract(.group, "miniwhisper.settings.microphone", "Microphone"),
        contract(
          .staticText, "miniwhisper.settings.microphone.state", "Microphone highlight",
          "Bar off",
        ),
        contract(
          .staticText, "miniwhisper.settings.microphone.level", "Microphone input level", "0.42",
        ),
        contract(
          .popUpButton, "miniwhisper.settings.microphone.picker", "Microphone input",
          "System Default (MacBook Pro Microphone)", isEnabled: true, isActionable: true,
        ),
        contract(.group, "miniwhisper.settings.sound.activate", "Activate"),
        contract(
          .staticText, "miniwhisper.settings.sound.activate.state", "Activate highlight",
          "Bar off",
        ),
        contract(
          .button, "miniwhisper.settings.sound.activate.preview",
          "Preview activate sound", "Ring off", isEnabled: true, isActionable: true,
        ),
        contract(
          .popUpButton, "miniwhisper.settings.sound.activate.picker", "Activate sound",
          "Tink (default)", isEnabled: true, isActionable: true,
        ),
        contract(
          .staticText, "miniwhisper.settings.sound.activate.picker.state",
          "Activate sound emphasis", "Primary",
        ),
        contract(.group, "miniwhisper.settings.sound.complete", "Complete"),
        contract(
          .staticText, "miniwhisper.settings.sound.complete.state", "Complete highlight", "Bar off",
        ),
        contract(
          .button, "miniwhisper.settings.sound.complete.preview", "Preview complete sound",
          "Ring off",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .popUpButton, "miniwhisper.settings.sound.complete.picker", "Complete sound",
          "Pop (default)",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .staticText, "miniwhisper.settings.sound.complete.picker.state",
          "Complete sound emphasis",
          "Primary",
        ),
        contract(.group, "miniwhisper.settings.sound.cancel", "Cancel"),
        contract(
          .staticText, "miniwhisper.settings.sound.cancel.state", "Cancel highlight", "Bar off",
        ),
        contract(
          .button, "miniwhisper.settings.sound.cancel.preview", "Preview cancel sound", "Ring off",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .popUpButton, "miniwhisper.settings.sound.cancel.picker", "Cancel sound",
          "Funk (default)",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .staticText, "miniwhisper.settings.sound.cancel.picker.state", "Cancel sound emphasis",
          "Primary",
        ),
        contract(.group, "miniwhisper.settings.sound.error", "Error"),
        contract(
          .staticText, "miniwhisper.settings.sound.error.state", "Error highlight", "Bar off",
        ),
        contract(
          .button, "miniwhisper.settings.sound.error.preview", "Preview error sound", "Ring off",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .popUpButton, "miniwhisper.settings.sound.error.picker", "Error sound",
          "Basso (default)",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .staticText, "miniwhisper.settings.sound.error.picker.state", "Error sound emphasis",
          "Primary",
        ),
        contract(
          .staticText, "miniwhisper.settings.sound.playback", "Sound playback", "None",
        ),
        contract(
          .switch, "miniwhisper.settings.launch-at-login", "Open at login", "1",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .staticText, "miniwhisper.settings.launch-at-login.state",
          "Open at login highlight", "Bar off",
        ),
        contract(
          .staticText, "miniwhisper.settings.launch-at-login.ring",
          "Open at login ring", "Ring off",
        ),
      ],
    )
  }

  @MainActor func testSettingsRepairRowsAreDegradedOnlyAndAreTheirOwnDoor() {
    // The healthy manifest rejects these rows as unexpected; this scene proves their degraded form.
    let app = launch("settings-degraded")
    defer { terminate(app) }
    let accessibility = app.groups["miniwhisper.settings.repair.accessibility"]
    let microphone = app.groups["miniwhisper.settings.repair.microphone"]
    let model = app.groups["miniwhisper.settings.repair.model-setup-failed"]
    XCTAssertTrue(accessibility.awaitExistence(timeout: 5))
    XCTAssertTrue(microphone.exists)
    XCTAssertTrue(model.exists)
    XCTAssertEqual(accessibility.label, "Required to start dictation and paste text")
    XCTAssertEqual(
      app.buttons["miniwhisper.settings.repair.accessibility.action"].label,
      "Grant Accessibility Access…",
    )
    XCTAssertEqual(
      app.buttons["miniwhisper.settings.repair.model-setup-failed.action"].label,
      "Retry Parakeet v2 Setup",
    )
    assertValue(
      "Speech model setup failed", of: app.staticTexts["miniwhisper.settings.engine-status"],
    )

    app.typeText("l")
    app.typeKey(.return, modifierFlags: [])
    waitForAgentResult(
      "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
    )
  }

  @MainActor func testSettingsNoAudioIsSecondaryAndCannotBePreviewed() {
    let app = launch("settings-sounds-no-audio")
    defer { terminate(app) }

    let picker = app.popUpButtons["miniwhisper.settings.sound.cancel.picker"]
    let preview = app.buttons["miniwhisper.settings.sound.cancel.preview"]
    XCTAssertTrue(picker.awaitExistence(timeout: 5))
    assertValue("No audio", of: picker)
    assertValue(
      "Secondary", of: app.staticTexts["miniwhisper.settings.sound.cancel.picker.state"],
    )
    XCTAssertFalse(preview.isEnabled)
  }

  @MainActor func testSettingsUnavailableMicrophoneShowsTruthfulFallback() {
    let app = launch("settings-microphone-unavailable")
    defer { terminate(app) }

    let picker = app.popUpButtons["miniwhisper.settings.microphone.picker"]
    let notice = app.descendants(matching: .any)["miniwhisper.settings.microphone.unavailable"]
    XCTAssertTrue(picker.awaitExistence(timeout: 5))
    XCTAssertTrue(picker.isEnabled)
    XCTAssertEqual(accessibilityValue(picker), "Studio Microphone (Unavailable)")
    // The default device name resolves after the pane appears, so the notice is polled: a fast
    // existence wait no longer grants the free second the old timer-based wait did.
    assertLabel(
      "Studio Microphone not connected. Using system default: MacBook Pro Microphone.",
      of: notice,
    )
  }

  @MainActor func testRealSettingsWindowLaws() {
    // The directly presented agent scene preserves focus and cannot exercise these paths.
    let app = launchRealSettings()
    defer { terminate(app) }

    let sidebar = app.outlines["miniwhisper.settings.sidebar"]
    let settings = app.staticTexts["miniwhisper.settings.sidebar.settings"]
    let history = app.staticTexts["miniwhisper.settings.sidebar.history"]
    assertValue("Focused", of: sidebar)
    assertValue("Settings; Selected", of: settings)

    app.typeText("j")
    assertValue("History; Selected", of: history)
    app.typeText("k")
    assertValue("Settings; Selected", of: settings)

    let bar = app.staticTexts["miniwhisper.settings.launch-at-login.state"]
    // One press per key: a repeated typeText is delivered whole, where a loop drops some.
    app.typeText("ljjjjjjjj")
    assertValue("Bar on", of: bar)

    app.typeText("hjkl")
    assertValue("Bar on", of: bar)
  }

  @MainActor func testAboutAccessibilityManifest() throws {
    try assertManifest(
      scene: "about",
      audits: true,
      elements: [
        contract(.window, "miniwhisper.about.window", "About \(appName)"),
        contract(.group, "miniwhisper.about.content", "About \(appName)"),
        contract(.image, "miniwhisper.about.icon", "\(appName) icon"),
        contract(.staticText, "miniwhisper.about.app-name", "Application", appName),
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
          .button, "miniwhisper.about.close", "Close About \(appName)", isEnabled: true,
          isActionable: true,
        ),
      ],
    )
  }

  @MainActor func testPillAccessibilityManifest() throws {
    let app = launch("pill-recording")
    defer { terminate(app) }
    try assertManifest(
      in: app,
      elements: [
        contract(.dialog, "miniwhisper.pill", "\(appName) dictation", "Visible"),
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
    presentScene("pill-transcribing")
    try assertManifest(
      in: app,
      elements: [
        contract(.dialog, "miniwhisper.pill", "\(appName) dictation", "Visible"),
        contract(.staticText, "miniwhisper.pill.phase", "Dictation phase", "Transcribing"),
      ],
    )
    presentScene("pill-no-speech")
    try assertManifest(
      in: app,
      elements: [
        contract(.dialog, "miniwhisper.pill", "\(appName) dictation", "Visible"),
        contract(.staticText, "miniwhisper.pill.phase", "Dictation phase", "No speech detected"),
        contract(.staticText, "miniwhisper.pill.notice", "Dictation notice", "No speech detected"),
      ],
    )
    presentScene("pill-copied")
    try assertManifest(
      in: app,
      elements: [
        contract(.dialog, "miniwhisper.pill", "\(appName) dictation", "Visible"),
        contract(.staticText, "miniwhisper.pill.phase", "Dictation phase", "Copied"),
        contract(
          .staticText, "miniwhisper.pill.notice", "Dictation notice", "Copied — ⌘V to paste",
        ),
      ],
    )
  }

  // MARK: Private

  @MainActor private func assertMenuManifest(
    scene: String, elements: [AccessibilityContract], file: StaticString = #filePath,
    line: UInt = #line,
  ) throws {
    let app = launch(scene)
    defer { terminate(app) }
    let statusItem = app.statusItems["miniwhisper.menu.status-item"]
    XCTAssertTrue(statusItem.awaitExistence(timeout: 5), file: file, line: line)
    XCTAssertEqual(statusItem.label, appName, file: file, line: line)
    XCTAssertTrue(statusItem.isEnabled, file: file, line: line)
    XCTAssertTrue(
      statusItem.isHittable, "Status item is hidden by menu bar overflow.", file: file, line: line,
    )
    statusItem.click()
    XCTAssertTrue(
      app.menuItems[elements[0].identifier].awaitExistence(timeout: 2), file: file, line: line,
    )
    assert(elements, in: app, file: file, line: line)
  }

  /// The audit is a property of a presented scene, not a scene of its own, so it rides along with
  /// the manifest that already has the window open.
  @MainActor private func assertManifest(
    scene: String, audits: Bool = false, elements: [AccessibilityContract],
    mutation: ((XCUIApplication) -> Void)? = nil, file: StaticString = #filePath,
    line: UInt = #line,
  ) throws {
    let app = launch(scene)
    defer { terminate(app) }
    try assertManifest(
      in: app, audits: audits, elements: elements, mutation: mutation, file: file, line: line,
    )
  }

  @MainActor private func assertManifest(
    in app: XCUIApplication, audits: Bool = false, elements: [AccessibilityContract],
    mutation: ((XCUIApplication) -> Void)? = nil, file: StaticString = #filePath,
    line: UInt = #line,
  ) throws {
    XCTAssertTrue(
      app.descendants(matching: .any)[elements[0].identifier].awaitExistence(timeout: 5),
      file: file, line: line,
    )
    assert(elements, in: app, allowing: menuKnownIdentifiers, file: file, line: line)
    if audits {
      try app.performAccessibilityAudit(for: [.elementDetection, .action])
    }
    mutation?(app)
  }

  @MainActor private func launchRealSettings() -> XCUIApplication {
    let app = XCUIApplication()
    app.launch()
    let statusItem = app.statusItems["miniwhisper.menu.status-item"]
    XCTAssertTrue(statusItem.awaitExistence(timeout: 5))
    statusItem.click()
    let settings = app.menuItems["miniwhisper.menu.settings"]
    XCTAssertTrue(settings.awaitExistence(timeout: 2))
    settings.click()
    XCTAssertTrue(app.windows["miniwhisper.settings.window"].awaitExistence(timeout: 5))
    return app
  }

  @MainActor private func assert(
    _ contracts: [AccessibilityContract], in app: XCUIApplication,
    allowing extraIdentifiers: Set<String> = [], file: StaticString, line: UInt,
  ) {
    let allowedIdentifiers = Set(contracts.map(\.identifier)).union(extraIdentifiers).union([
      "miniwhisper.menu.status-item",
    ])
    var snapshots: [String: [XCUIElementSnapshot]] = [:]
    var snapshotError: Error?
    // The settle condition also demands that nothing beyond the manifest is on screen: after a
    // scene swap, the previous scene's elements are still real until the tree repaints, and
    // waiting only for the new ones would let a stale frame fail the unexpected-identifier claim.
    let settled = poll(timeout: 2) {
      do {
        snapshots = try self.accessibilitySnapshots(app.snapshot())
        return contracts.allSatisfy { contract in
          guard snapshots[contract.identifier]?.count == 1,
                let snapshot = snapshots[contract.identifier]?.first
          else {
            return false
          }
          return contract.value.map { self.accessibilityValue(snapshot) == $0 } ?? true
        } && Set(snapshots.keys).subtracting(allowedIdentifiers).isEmpty
      } catch {
        snapshotError = error
        return false
      }
    }
    if snapshots.isEmpty {
      XCTFail(
        "Could not snapshot the application: \(snapshotError.map(String.init(describing:)) ?? "unknown error")",
        file: file,
        line: line,
      )
      return
    }
    if !settled {
      XCTFail("Accessibility tree did not settle", file: file, line: line)
    }

    for contract in contracts {
      let matches = snapshots[contract.identifier, default: []]
      XCTAssertEqual(
        matches.count, 1, "Expected one \(contract.identifier)", file: file, line: line,
      )
      guard let snapshot = matches.first else {
        continue
      }
      XCTAssertEqual(
        snapshot.elementType, contract.elementType, contract.identifier, file: file, line: line,
      )
      XCTAssertFalse(
        snapshot.label.isEmpty, "\(contract.identifier) has no label", file: file, line: line,
      )
      XCTAssertEqual(snapshot.label, contract.label, contract.identifier, file: file, line: line)
      if let value = contract.value {
        XCTAssertEqual(
          accessibilityValue(snapshot), value, contract.identifier, file: file, line: line,
        )
      }
      if let valuePattern = contract.valuePattern {
        XCTAssertNotNil(
          accessibilityValue(snapshot).range(of: valuePattern, options: .regularExpression),
          contract.identifier, file: file, line: line,
        )
      }
      if let isEnabled = contract.isEnabled {
        XCTAssertEqual(snapshot.isEnabled, isEnabled, contract.identifier, file: file, line: line)
      }
      if contract.isActionable {
        let element = app.descendants(matching: .any)[contract.identifier]
        XCTAssertTrue(snapshot.isEnabled, contract.identifier, file: file, line: line)
        XCTAssertTrue(element.isHittable, contract.identifier, file: file, line: line)
      }
    }

    let duplicateIdentifiers = snapshots.filter { $0.value.count > 1 }
    XCTAssertTrue(
      duplicateIdentifiers.isEmpty, "Duplicate identifiers: \(duplicateIdentifiers.keys.sorted())",
      file: file, line: line,
    )

    let unexpectedIdentifiers = Set(snapshots.keys).subtracting(allowedIdentifiers)
    XCTAssertTrue(
      unexpectedIdentifiers.isEmpty, "Unexpected identifiers: \(unexpectedIdentifiers.sorted())",
      file: file, line: line,
    )
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
      contract(.window, "miniwhisper.onboarding.window", "Set Up \(appName)"),
      contract(.group, "miniwhisper.onboarding.rail", "Setup steps"),
      contract(.staticText, "miniwhisper.onboarding.rail.brand", "Application name", appName),
      contract(
        .staticText, "miniwhisper.onboarding.rail.tagline", "Application description",
        "fast and accurate dictation",
      ),
      contract(
        .button, "miniwhisper.onboarding.rail.permissions", "Permissions", values[0],
        isEnabled: true, isActionable: true,
      ),
      contract(
        .button, "miniwhisper.onboarding.rail.shortcut", "Shortcut", values[1], isEnabled: true,
        isActionable: true,
      ),
      contract(
        .button, "miniwhisper.onboarding.rail.model", "Speech Model", values[2], isEnabled: true,
        isActionable: true,
      ),
      contract(
        .button, "miniwhisper.onboarding.rail.try-it", "Try It", values[3], isEnabled: true,
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
    ["Current", "Available", "Available; Downloading 42%", "Available"]
  }
}

private let menuKnownIdentifiers: Set<String> = [
  "miniwhisper.menu.status", "miniwhisper.menu.repair.accessibility",
  "miniwhisper.menu.repair.microphone", "miniwhisper.menu.copy-last-transcript",
  "miniwhisper.menu.settings", "miniwhisper.menu.about", "miniwhisper.menu.quit",
]
