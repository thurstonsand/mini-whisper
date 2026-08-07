import AppKit
import ApplicationServices
import XCTest

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
      try assertManifest(
        scene: permission.scene,
        elements: onboardingRail(permission.railValues) + permissionElements(permission),
      )
    }

    try assertManifest(
      scene: "onboarding-shortcut",
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

    try assertManifest(
      scene: "onboarding-model",
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

    try assertManifest(
      scene: "onboarding-try-it",
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

    try assertManifest(
      scene: "onboarding-ready",
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
          .menuItem, "miniwhisper.menu.launch-at-login", "Launch at Login", "On", isEnabled: true,
          isActionable: true,
        ),
        contract(
          .menuItem, "miniwhisper.menu.settings-file", "Open Settings File", isEnabled: true,
          isActionable: true,
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
          .menuItem, "miniwhisper.menu.launch-at-login", "Launch at Login", "Off", isEnabled: true,
          isActionable: true,
        ),
        contract(
          .menuItem, "miniwhisper.menu.settings-file", "Open Settings File", isEnabled: true,
          isActionable: true,
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
          "Preview record start sound", "Ring off", isEnabled: true, isActionable: true,
        ),
        contract(
          .popUpButton, "miniwhisper.settings.sound.activate.picker", "Activate sound",
          "Tink (default)", isEnabled: true, isActionable: true,
        ),
        contract(
          .staticText, "miniwhisper.settings.sound.activate.picker.state",
          "Record start sound emphasis", "Primary",
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
      ],
    )
  }

  @MainActor func testSettingsMicrophoneRowJoinsTheKeyboardGrammar() {
    let app = launch("settings")
    defer { terminate(app) }

    let picker = app.popUpButtons["miniwhisper.settings.microphone.picker"]
    let rowState = app.staticTexts["miniwhisper.settings.microphone.state"]
    XCTAssertTrue(picker.waitForExistence(timeout: 5))

    app.typeText("lj")
    assertValue("Bar on", of: rowState)
    assertValue("Bar off", of: app.staticTexts["miniwhisper.settings.shortcut.activate.state"])

    app.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(
      app.menuItems["System Default (MacBook Pro Microphone)"].waitForExistence(timeout: 2),
    )
    app.typeKey(.escape, modifierFlags: [])
  }

  @MainActor func testSettingsSoundRowsJoinTheKeyboardGrammar() {
    let app = launch("settings")
    defer { terminate(app) }

    XCTAssertTrue(
      app.popUpButtons["miniwhisper.settings.sound.error.picker"].waitForExistence(timeout: 5),
    )
    app.typeText("l")
    for cue in ["microphone", "sound.activate", "sound.complete", "sound.cancel", "sound.error"] {
      app.typeText("j")
      assertValue("Bar on", of: app.staticTexts["miniwhisper.settings.\(cue).state"])
    }
    app.typeText("kkkkk")
    assertValue(
      "Bar on", of: app.staticTexts["miniwhisper.settings.shortcut.activate.state"],
    )
  }

  @MainActor func testSettingsReturnOpensASoundPopup() {
    let app = launch("settings")
    defer { terminate(app) }

    let picker = app.popUpButtons["miniwhisper.settings.sound.activate.picker"]
    XCTAssertTrue(picker.waitForExistence(timeout: 5))
    app.typeText("ljj")
    assertValue(
      "Bar on", of: app.staticTexts["miniwhisper.settings.sound.activate.state"],
    )
    app.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(app.menuItems["No audio"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.menuItems["Tink (default)"].exists)
    app.typeKey(.escape, modifierFlags: [])

    app.typeText("h")
    assertValue("Focused", of: app.outlines["miniwhisper.settings.sidebar"])
  }

  @MainActor func testSettingsNoAudioIsSecondaryAndCannotBePreviewed() {
    let app = launch("settings-sounds-no-audio")
    defer { terminate(app) }

    let picker = app.popUpButtons["miniwhisper.settings.sound.cancel.picker"]
    let preview = app.buttons["miniwhisper.settings.sound.cancel.preview"]
    XCTAssertTrue(picker.waitForExistence(timeout: 5))
    assertValue("No audio", of: picker)
    assertValue(
      "Secondary", of: app.staticTexts["miniwhisper.settings.sound.cancel.picker.state"],
    )
    XCTAssertFalse(preview.isEnabled)
  }

  @MainActor func testSettingsSoundPreviewFiresTheInjectedClient() {
    let app = launch("settings")
    defer { terminate(app) }

    let preview = app.buttons["miniwhisper.settings.sound.activate.preview"]
    XCTAssertTrue(preview.waitForExistence(timeout: 5))
    preview.click()
    assertValue("Tink", of: app.staticTexts["miniwhisper.settings.sound.playback"])
  }

  @MainActor func testSettingsMicrophoneRowAnswersThePointer() {
    let app = launch("settings")
    defer { terminate(app) }

    let picker = app.popUpButtons["miniwhisper.settings.microphone.picker"]
    let rowState = app.staticTexts["miniwhisper.settings.microphone.state"]
    XCTAssertTrue(picker.waitForExistence(timeout: 5))

    hoverAfterEnteringWindow(
      app.descendants(matching: .any)["miniwhisper.settings.microphone"], in: app,
    )
    assertValue("Bar on", of: rowState)

    picker.click()
    let studio = app.menuItems["Studio Microphone"]
    XCTAssertTrue(studio.waitForExistence(timeout: 2))
    studio.click()
    assertValue("Studio Microphone", of: picker)
  }

  @MainActor func testSettingsUnavailableMicrophoneShowsTruthfulFallback() {
    let app = launch("settings-microphone-unavailable")
    defer { terminate(app) }

    let picker = app.popUpButtons["miniwhisper.settings.microphone.picker"]
    let notice = app.descendants(matching: .any)["miniwhisper.settings.microphone.unavailable"]
    XCTAssertTrue(picker.waitForExistence(timeout: 5))
    XCTAssertTrue(picker.isEnabled)
    XCTAssertEqual(accessibilityValue(picker), "Studio Microphone (Unavailable)")
    XCTAssertEqual(
      notice.label,
      "Studio Microphone not connected. Using system default: MacBook Pro Microphone.",
    )
  }

  @MainActor func testSettingsRealWindowStartsInSidebar() {
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
  }

  @MainActor func testSettingsEnteringDetailPaintsCursor() {
    let app = launch("settings")
    defer { terminate(app) }

    app.typeText("jkl")
    assertValue("Not focused", of: app.outlines["miniwhisper.settings.sidebar"])
    assertValue(
      "Bar on", of: app.staticTexts["miniwhisper.settings.shortcut.activate.state"],
    )
    assertValue(
      "Ring on", of: app.buttons["miniwhisper.settings.shortcut.binding.0"],
    )
  }

  @MainActor func testSettingsReturningToSidebarClearsCursorPaint() {
    let app = launch("settings")
    defer { terminate(app) }

    app.typeText("lh")
    assertValue("Focused", of: app.outlines["miniwhisper.settings.sidebar"])
    assertValue(
      "Bar off", of: app.staticTexts["miniwhisper.settings.shortcut.activate.state"],
    )
    assertValue(
      "Ring off", of: app.buttons["miniwhisper.settings.shortcut.binding.0"],
    )
  }

  @MainActor func testSettingsHoverSurvivesKeyboardModeEntry() {
    let app = launch("settings")
    defer { terminate(app) }

    app.typeText("l")
    let row = app.groups["miniwhisper.settings.shortcut.activate"]
    let rowState = app.staticTexts["miniwhisper.settings.shortcut.activate.state"]
    let binding = app.buttons["miniwhisper.settings.shortcut.binding.0"]
    hoverAfterEnteringWindow(row, in: app)
    assertValue("Bar on", of: rowState)
    assertValue("Ring off", of: binding)

    // `k` at the top of the list moves nowhere, so what this observes is only the handover: the
    // keyboard takes back a cursor that was already standing where the pointer was.
    app.typeText("k")
    assertValue("Bar on", of: rowState)
    assertValue("Ring on", of: binding)
  }

  @MainActor func testSettingsKeyboardMovementContinuesFromHoveredRow() {
    let app = launch("settings")
    defer { terminate(app) }

    app.typeText("l")
    let errorRow = app.groups["miniwhisper.settings.sound.error"]
    XCTAssertTrue(errorRow.waitForExistence(timeout: 5))
    hoverAfterEnteringWindow(errorRow, in: app)
    assertValue(
      "Bar on", of: app.staticTexts["miniwhisper.settings.sound.error.state"],
    )

    app.typeText("k")
    assertValue(
      "Bar on", of: app.staticTexts["miniwhisper.settings.sound.cancel.state"],
    )
    assertValue(
      "Ring off", of: app.buttons["miniwhisper.settings.sound.cancel.preview"],
    )
  }

  @MainActor func testHistoryEnteringFromSidebarPaintsFirstCursor() {
    let app = launch("settings-history")
    defer { terminate(app) }

    let firstRow = historyRow(app, id: "11111111-1111-1111-1111-111111111111")
    XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
    app.typeText("h")
    assertValue("Focused", of: app.outlines["miniwhisper.settings.sidebar"])
    app.typeText("l")
    assertValue("Not focused", of: app.outlines["miniwhisper.settings.sidebar"])
    assertValue(
      "Grey on; Cursor on; Copied off",
      of: historyRowState(app, id: "11111111-1111-1111-1111-111111111111"),
    )
  }

  @MainActor func testHistoryMovementKeepsExactlyOneGreyRow() {
    let app = launch("settings-history")
    defer { terminate(app) }

    XCTAssertTrue(historyRows(app).firstMatch.waitForExistence(timeout: 5))
    app.typeText("j")
    assertSingleGreyHistoryRow(app, id: "22222222-2222-2222-2222-222222222222")
    app.typeText("k")
    assertSingleGreyHistoryRow(app, id: "11111111-1111-1111-1111-111111111111")
  }

  @MainActor func testHistoryCopyKeepsCursor() {
    let app = launch("settings-history")
    defer { terminate(app) }

    let firstID = "11111111-1111-1111-1111-111111111111"
    let firstRow = historyRow(app, id: firstID)
    XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
    app.typeText("l")
    XCTAssertTrue(
      app.descendants(matching: .any)["miniwhisper.history.copied.\(firstID)"]
        .waitForExistence(timeout: 2),
    )
    XCTAssertTrue(accessibilityValue(historyRowState(app, id: firstID)).contains("Cursor on"))
  }

  @MainActor func testHistoryRoundTripRestoresSameCursor() {
    let app = launch("settings-history")
    defer { terminate(app) }

    XCTAssertTrue(historyRows(app).firstMatch.waitForExistence(timeout: 5))
    let secondID = "22222222-2222-2222-2222-222222222222"
    app.typeText("jh")
    XCTAssertTrue(
      historyRowStates(app).allElementsBoundByIndex.allSatisfy {
        !accessibilityValue($0).contains("Grey on")
      },
    )
    app.typeText("l")
    assertSingleGreyHistoryRow(app, id: secondID)
  }

  @MainActor func testHistoryParkedPointerCannotStealKeyboardGrey() {
    let app = launch("settings-history")
    defer { terminate(app) }

    let firstRow = historyRow(app, id: "11111111-1111-1111-1111-111111111111")
    XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
    firstRow.hover()
    app.typeText("jj")
    assertSingleGreyHistoryRow(app, id: "00000000-0000-0000-0000-000000000003")
  }

  @MainActor func testHistorySearchFocusAndExitLaws() {
    let app = launch("settings-history")
    defer { terminate(app) }

    XCTAssertTrue(historyRows(app).firstMatch.waitForExistence(timeout: 5))
    app.typeText("/")
    let search = app.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 2))
    search.typeText("second")
    XCTAssertTrue(
      historyRowStates(app).allElementsBoundByIndex.allSatisfy {
        !accessibilityValue($0).contains("Grey on")
      },
    )
    search.typeKey(.return, modifierFlags: [])
    let secondID = "22222222-2222-2222-2222-222222222222"
    assertSingleGreyHistoryRow(app, id: secondID)

    app.typeText("/")
    search.typeKey(.escape, modifierFlags: [])
    assertValue("", of: search)
  }

  @MainActor func testHistorySettingsInteractions() throws {
    let app = launch("settings-history")
    defer { terminate(app) }

    let firstID = "11111111-1111-1111-1111-111111111111"
    let secondID = "22222222-2222-2222-2222-222222222222"
    let firstRow = app.descendants(matching: .any)["miniwhisper.history.row.\(firstID)"]
    let secondRow = app.descendants(matching: .any)["miniwhisper.history.row.\(secondID)"]
    XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
    XCTAssertTrue(secondRow.exists)

    firstRow.click()
    XCTAssertTrue(
      app.descendants(matching: .any)["miniwhisper.history.copied.\(firstID)"]
        .waitForExistence(timeout: 2),
    )

    // The copy toast lands before the toolbar settles, so hittability is waited on rather than
    // sampled the instant the click returns.
    let storage = app.buttons["miniwhisper.history.storage"]
    let hittable = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "isHittable == true"), object: storage,
    )
    XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 3), .completed)
    storage.click()
    XCTAssertTrue(
      app.descendants(matching: .any)["miniwhisper.history.storage.popover"]
        .waitForExistence(timeout: 2),
    )
    app.typeKey(.escape, modifierFlags: [])

    secondRow.rightClick()
    XCTAssertTrue(app.menuItems
      .matching(identifier: "Delete")
      .firstMatch
      .waitForExistence(timeout: 2))
    let delete = try XCTUnwrap(
      app.menuItems
        .matching(identifier: "Delete")
        .allElementsBoundByIndex
        .first(where: \.isHittable),
    )
    delete.click()
    XCTAssertEqual(waitForDisappearance(of: secondRow), .completed)
  }

  @MainActor func testHistoryVimLoop() {
    let app = launch("settings-history")
    defer { terminate(app) }

    let secondID = "22222222-2222-2222-2222-222222222222"
    XCTAssertTrue(
      app.descendants(matching: .any)["miniwhisper.history.row.\(secondID)"]
        .waitForExistence(timeout: 5),
    )

    // The cursor starts on the first row, so one j reaches the second; l copies where it landed.
    app.typeText("jl")
    XCTAssertTrue(
      app.descendants(matching: .any)["miniwhisper.history.copied.\(secondID)"]
        .waitForExistence(timeout: 2),
    )

    // h leaves for the sidebar, where j walks destinations and l dives back in.
    app.typeText("hj")
    let placeholder = app.descendants(matching: .any)["miniwhisper.settings.placeholder"]
    XCTAssertTrue(placeholder.waitForExistence(timeout: 2))
    XCTAssertTrue(placeholder.label.hasPrefix("Model"))

    app.typeText("k")
    let firstID = "11111111-1111-1111-1111-111111111111"
    let firstRow = app.descendants(matching: .any)["miniwhisper.history.row.\(firstID)"]
    XCTAssertTrue(firstRow.waitForExistence(timeout: 2))

    // The cursor survived the round trip, so l copies the row it was left on.
    app.typeText("ll")
    XCTAssertTrue(
      app.descendants(matching: .any)["miniwhisper.history.copied.\(secondID)"]
        .waitForExistence(timeout: 2),
    )

    // The search field keeps the keys it is given: vim navigation must not claim focus back.
    let search = app.searchFields.firstMatch
    XCTAssertTrue(search.waitForExistence(timeout: 2))
    search.click()
    search.typeText("keyboard")
    let filteredOut = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"), object: firstRow,
    )
    XCTAssertEqual(XCTWaiter.wait(for: [filteredOut], timeout: 3), .completed)
  }

  @MainActor func testHistorySearchKeys() {
    let app = launch("settings-history")
    defer { terminate(app) }

    let firstID = "11111111-1111-1111-1111-111111111111"
    let filteredID = "00000000-0000-0000-0000-000000000003"
    let firstRow = app.descendants(matching: .any)["miniwhisper.history.row.\(firstID)"]
    XCTAssertTrue(firstRow.waitForExistence(timeout: 5))

    // "/" hands the keys to the search field, and Return hands them back with the filter intact.
    app.typeText("/")
    app.typeText("keyboard")
    XCTAssertEqual(waitForDisappearance(of: firstRow), .completed)
    app.typeKey(.return, modifierFlags: [])
    app.typeText("l")
    XCTAssertTrue(
      app.descendants(matching: .any)["miniwhisper.history.copied.\(filteredID)"]
        .waitForExistence(timeout: 2),
    )

    // Escape abandons the query instead, and still hands the keys back — to a cursor that stayed
    // where the filtered list left it, so k reaches the row above the one Return copied.
    let secondID = "22222222-2222-2222-2222-222222222222"
    app.typeText("/")
    app.typeText("xyzzy")
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(firstRow.waitForExistence(timeout: 2))
    app.typeText("kl")
    XCTAssertTrue(
      app.descendants(matching: .any)["miniwhisper.history.copied.\(secondID)"]
        .waitForExistence(timeout: 2),
    )
  }

  @MainActor func testAboutAccessibilityManifest() throws {
    try assertManifest(
      scene: "about",
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
    try assertManifest(
      scene: "pill-recording",
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
    try assertManifest(
      scene: "pill-transcribing",
      elements: [
        contract(.dialog, "miniwhisper.pill", "\(appName) dictation", "Visible"),
        contract(.staticText, "miniwhisper.pill.phase", "Dictation phase", "Transcribing"),
      ],
    )
    try assertManifest(
      scene: "pill-no-speech",
      elements: [
        contract(.dialog, "miniwhisper.pill", "\(appName) dictation", "Visible"),
        contract(.staticText, "miniwhisper.pill.phase", "Dictation phase", "No speech detected"),
        contract(.staticText, "miniwhisper.pill.notice", "Dictation notice", "No speech detected"),
      ],
    )
    try assertManifest(
      scene: "pill-copied",
      elements: [
        contract(.dialog, "miniwhisper.pill", "\(appName) dictation", "Visible"),
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

  // MARK: Private

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
    XCTAssertEqual(statusItem.label, appName, file: file, line: line)
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

  @MainActor private func launchRealSettings() -> XCUIApplication {
    let app = XCUIApplication()
    app.launch()
    let statusItem = app.statusItems["miniwhisper.menu.status-item"]
    XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
    statusItem.click()
    let settings = app.menuItems["miniwhisper.menu.settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 2))
    settings.click()
    XCTAssertTrue(app.windows["miniwhisper.settings.window"].waitForExistence(timeout: 5))
    return app
  }

  private func historyRows(_ app: XCUIApplication) -> XCUIElementQuery {
    app.descendants(matching: .any).matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND NOT identifier ENDSWITH %@",
        "miniwhisper.history.row.", ".state",
      ),
    )
  }

  private func historyRowStates(_ app: XCUIApplication) -> XCUIElementQuery {
    app.descendants(matching: .any).matching(
      NSPredicate(
        format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@",
        "miniwhisper.history.row.", ".state",
      ),
    )
  }

  private func historyRow(_ app: XCUIApplication, id: String) -> XCUIElement {
    app.descendants(matching: .any)["miniwhisper.history.row.\(id)"]
  }

  private func historyRowState(_ app: XCUIApplication, id: String) -> XCUIElement {
    app.staticTexts["miniwhisper.history.row.\(id).state"]
  }

  private func assertSingleGreyHistoryRow(
    _ app: XCUIApplication, id: String, file: StaticString = #filePath, line: UInt = #line,
  ) {
    let states = historyRowStates(app).allElementsBoundByIndex
    let greyStates = states.filter { accessibilityValue($0).contains("Grey on") }
    XCTAssertEqual(greyStates.count, 1, file: file, line: line)
    XCTAssertEqual(
      greyStates.first?.identifier,
      "miniwhisper.history.row.\(id).state",
      file: file,
      line: line,
    )
    XCTAssertTrue(
      accessibilityValue(historyRowState(app, id: id)).contains("Cursor on"),
      file: file,
      line: line,
    )
  }

  private func recordSpikeEvidence(_ evidence: String) {
    print("RAW_AX_SPIKE: \(evidence)")
    let attachment = XCTAttachment(string: evidence)
    attachment.lifetime = .keepAlways
    add(attachment)
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
  "miniwhisper.menu.status", "miniwhisper.menu.repair", "miniwhisper.menu.copy-last-transcript",
  "miniwhisper.menu.sounds", "miniwhisper.menu.launch-at-login", "miniwhisper.menu.settings-file",
  "miniwhisper.menu.settings", "miniwhisper.menu.about", "miniwhisper.menu.quit",
]
