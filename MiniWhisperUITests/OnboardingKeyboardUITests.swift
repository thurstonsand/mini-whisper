import XCTest

/// Onboarding's keyboard grammar, asserted the way a user meets it: Return does the visible step's
/// one job, and Tab visits only the controls that step actually offers.
final class OnboardingKeyboardUITests: XCTestCase {
  // MARK: Internal

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  // MARK: Return

  @MainActor func testWelcomeReturnStartsDownload() {
    let app = launch("onboarding-welcome")
    defer { terminate(app) }

    XCTAssertTrue(
      app.buttons["miniwhisper.onboarding.download-model"].waitForExistence(timeout: 5),
    )
    app.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(app.groups["miniwhisper.onboarding.permissions"].waitForExistence(timeout: 2))
  }

  @MainActor func testPermissionsReturnGrantsActivePermissionInOrder() {
    let app = launch("onboarding-permissions-microphone")
    defer { terminate(app) }

    let microphone = app.buttons["miniwhisper.onboarding.permission.microphone.action"]
    XCTAssertTrue(microphone.waitForExistence(timeout: 5))
    XCTAssertEqual(microphone.label, "Grant Microphone")
    app.typeKey(.return, modifierFlags: [])

    let accessibility = app.buttons["miniwhisper.onboarding.permission.accessibility.action"]
    XCTAssertTrue(accessibility.waitForExistence(timeout: 2))
    XCTAssertEqual(accessibility.label, "Grant Accessibility")
    app.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(app.groups["miniwhisper.onboarding.shortcut"].waitForExistence(timeout: 2))
  }

  @MainActor func testPermissionsReturnOpensSettingsWhenRequired() {
    let app = launch("onboarding-permissions-accessibility-settings")
    defer { terminate(app) }

    let action = app.buttons["miniwhisper.onboarding.permission.accessibility.action"]
    XCTAssertTrue(action.waitForExistence(timeout: 5))
    XCTAssertEqual(action.label, "Open Accessibility Settings")
    app.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(
      app.descendants(matching: .any)["miniwhisper.onboarding.failure"]
        .waitForExistence(timeout: 2),
    )
  }

  @MainActor func testShortcutReturnContinuesToModel() {
    let app = launch("onboarding-shortcut")
    defer { terminate(app) }

    XCTAssertTrue(
      app.buttons["miniwhisper.onboarding.shortcut.continue"].waitForExistence(timeout: 5),
    )
    app.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(app.groups["miniwhisper.onboarding.model"].waitForExistence(timeout: 2))
  }

  @MainActor func testModelReturnRetriesSetup() {
    let app = launch("onboarding-model-actionable")
    defer { terminate(app) }

    let failure = app.descendants(matching: .any)["miniwhisper.onboarding.failure"]
    XCTAssertTrue(failure.waitForExistence(timeout: 5))
    app.typeKey(.return, modifierFlags: [])
    XCTAssertEqual(waitForDisappearance(of: failure), .completed)
  }

  @MainActor func testReadyReturnFinishes() {
    let app = launch("onboarding-ready")
    defer { terminate(app) }

    let ready = app.groups["miniwhisper.onboarding.ready"]
    XCTAssertTrue(ready.waitForExistence(timeout: 5))
    app.typeKey(.return, modifierFlags: [])
    XCTAssertEqual(waitForDisappearance(of: ready), .completed)
  }

  // MARK: Tab

  @MainActor func testSingleActionPagesExcludeRailFromTabOrder() {
    let pages = [
      ("onboarding-welcome", "miniwhisper.onboarding.download-model"),
      (
        "onboarding-permissions-microphone",
        "miniwhisper.onboarding.permission.microphone.action",
      ),
      (
        "onboarding-permissions-accessibility-settings",
        "miniwhisper.onboarding.permission.accessibility.action",
      ),
      ("onboarding-model-actionable", "miniwhisper.onboarding.model.retry"),
      ("onboarding-ready", "miniwhisper.onboarding.ready.finish"),
    ]

    for (scene, identifier) in pages {
      let app = launch(scene)
      let action = app.buttons[identifier]
      XCTAssertTrue(action.waitForExistence(timeout: 5), scene)

      for modifiers: XCUIElement.KeyModifierFlags in [[], [], [.shift], [.shift]] {
        app.typeKey(.tab, modifierFlags: modifiers)
        assertKeyboardFocus(on: action)
      }

      terminate(app)
    }
  }

  @MainActor func testModelProgressHasNoTabStops() {
    let app = launch("onboarding-model")
    defer { terminate(app) }

    XCTAssertTrue(app.groups["miniwhisper.onboarding.model"].waitForExistence(timeout: 5))
    for modifiers: XCUIElement.KeyModifierFlags in [[], [], [.shift], [.shift]] {
      app.typeKey(.tab, modifierFlags: modifiers)
      assertOnlyWindowHasKeyboardFocus(in: app)
    }
  }

  @MainActor func testShortcutTabCyclesOnlyBetweenKeycapAndContinue() {
    let app = launch("onboarding-shortcut")
    defer { terminate(app) }

    let keycap = app.buttons["miniwhisper.onboarding.shortcut.binding"]
    let ring = app.staticTexts["miniwhisper.onboarding.shortcut.binding.state"]
    let continueButton = app.buttons["miniwhisper.onboarding.shortcut.continue"]
    XCTAssertTrue(keycap.waitForExistence(timeout: 5))
    assertValue("Ring off", of: ring)
    let entryScreenshot = app.screenshot()
    recordScreenshot("shortcut-entry", screenshot: entryScreenshot)
    let entryPixels = focusRingPixelCount(in: entryScreenshot, around: keycap)
    XCTAssertEqual(entryPixels, 0, "The keycap is painted as focused on entry")

    // The page opens unfocused, so the very first Tab is the keycap's — no searching for it.
    app.typeKey(.tab, modifierFlags: [])
    assertValue("Ring on", of: ring)
    let focusedScreenshot = app.screenshot()
    recordScreenshot("shortcut-keycap-focused", screenshot: focusedScreenshot)
    XCTAssertGreaterThan(
      focusRingPixelCount(in: focusedScreenshot, around: keycap), entryPixels + 20,
    )

    app.typeKey(.tab, modifierFlags: [])
    assertValue("Ring off", of: ring)
    assertKeyboardFocus(on: continueButton)

    // A 2-cycle is its own reverse, so Shift-Tab walks the same two stops.
    for modifiers: XCUIElement.KeyModifierFlags in [[], [], [.shift], [.shift]] {
      app.typeKey(.tab, modifierFlags: modifiers)
      assertValue("Ring on", of: ring)
      app.typeKey(.tab, modifierFlags: modifiers)
      assertValue("Ring off", of: ring)
      assertKeyboardFocus(on: continueButton)
    }
  }

  @MainActor func testTryItTabCyclesOnlyBetweenEditorAndSkip() {
    let app = launch("onboarding-try-it")
    defer { terminate(app) }

    let editor = app.textViews["miniwhisper.onboarding.try-it.text"]
    let skip = app.buttons["miniwhisper.onboarding.try-it.skip"]
    let skipRing = app.staticTexts["miniwhisper.onboarding.try-it.skip.state"]
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    assertKeyboardFocus(on: editor)
    assertValue("Ring off", of: skipRing)
    let entryScreenshot = app.screenshot()
    recordScreenshot("try-it-entry", screenshot: entryScreenshot)
    let entryPixels = focusRingPixelCount(in: entryScreenshot, around: skip)
    XCTAssertEqual(entryPixels, 0, "Skip is painted as focused on entry")

    app.typeKey(.tab, modifierFlags: [])
    assertKeyboardFocus(on: skip)
    assertValue("Ring on", of: skipRing)
    let focusedScreenshot = app.screenshot()
    recordScreenshot("try-it-skip-focused", screenshot: focusedScreenshot)
    XCTAssertGreaterThan(
      focusRingPixelCount(in: focusedScreenshot, around: skip), entryPixels + 20,
    )

    app.typeKey(.tab, modifierFlags: [])
    assertKeyboardFocus(on: editor)
    assertValue("Ring off", of: skipRing)

    for modifiers: XCUIElement.KeyModifierFlags in [[], [.shift], [.shift]] {
      app.typeKey(.tab, modifierFlags: modifiers)
      assertKeyboardFocus(on: skip)
      app.typeKey(.tab, modifierFlags: modifiers)
      assertKeyboardFocus(on: editor)
    }
  }

  @MainActor func testShortcutRailRoundTripLeavesTheKeycapUnfocused() {
    let app = launch("onboarding-shortcut")
    defer { terminate(app) }

    let keycap = app.buttons["miniwhisper.onboarding.shortcut.binding"]
    let ring = app.staticTexts["miniwhisper.onboarding.shortcut.binding.state"]
    XCTAssertTrue(keycap.waitForExistence(timeout: 5))
    app.typeKey(.tab, modifierFlags: [])
    assertValue("Ring on", of: ring)

    app.buttons["miniwhisper.onboarding.rail.permissions"].click()
    XCTAssertTrue(app.groups["miniwhisper.onboarding.permissions"].waitForExistence(timeout: 2))
    app.buttons["miniwhisper.onboarding.rail.shortcut"].click()
    XCTAssertTrue(keycap.waitForExistence(timeout: 2))

    assertValue("Ring off", of: ring)
    let screenshot = app.screenshot()
    recordScreenshot("shortcut-rail-round-trip", screenshot: screenshot)
    XCTAssertEqual(
      focusRingPixelCount(in: screenshot, around: keycap), 0,
      "The keycap kept its ring across a rail round trip",
    )
  }

  /// Focus does not leave with the view that held it. Walking the rail off Try It and back must
  /// not bring the old ring back with it.
  @MainActor func testTryItRailRoundTripReturnsFocusToTheEditor() {
    let app = launch("onboarding-try-it")
    defer { terminate(app) }

    let editor = app.textViews["miniwhisper.onboarding.try-it.text"]
    let skip = app.buttons["miniwhisper.onboarding.try-it.skip"]
    let skipRing = app.staticTexts["miniwhisper.onboarding.try-it.skip.state"]
    XCTAssertTrue(editor.waitForExistence(timeout: 5))
    app.typeKey(.tab, modifierFlags: [])
    assertKeyboardFocus(on: skip)

    app.buttons["miniwhisper.onboarding.rail.permissions"].click()
    XCTAssertTrue(app.groups["miniwhisper.onboarding.permissions"].waitForExistence(timeout: 2))
    app.buttons["miniwhisper.onboarding.rail.try-it"].click()
    XCTAssertTrue(editor.waitForExistence(timeout: 2))

    assertKeyboardFocus(on: editor)
    assertValue("Ring off", of: skipRing)
    let screenshot = app.screenshot()
    recordScreenshot("try-it-rail-round-trip", screenshot: screenshot)
    XCTAssertEqual(
      focusRingPixelCount(in: screenshot, around: skip), 0,
      "Skip kept its ring across a rail round trip",
    )
  }

  /// Entry focus is not only a launch-time story: the model finishing behind the user's back
  /// swaps the page under them, and the caret has to land in the editor there too.
  @MainActor func testTryItTakesFocusWhenTheModelFinishesBehindIt() {
    let app = launch("onboarding-shortcut")
    defer { terminate(app) }

    XCTAssertTrue(
      app.buttons["miniwhisper.onboarding.shortcut.continue"].waitForExistence(timeout: 5),
    )
    app.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(app.groups["miniwhisper.onboarding.model"].waitForExistence(timeout: 2))

    postAgentMutation("model-ready", value: "now")
    let editor = app.textViews["miniwhisper.onboarding.try-it.text"]
    XCTAssertTrue(editor.waitForExistence(timeout: 3))
    assertKeyboardFocus(on: editor)
    assertValue("Ring off", of: app.staticTexts["miniwhisper.onboarding.try-it.skip.state"])
    // Skip materialises with the page rather than with the window, which is the one moment AppKit
    // gets to pick a key view of its own. Pixels are the only witness that it did not.
    let screenshot = app.screenshot()
    recordScreenshot("try-it-after-transition", screenshot: screenshot)
    XCTAssertEqual(
      focusRingPixelCount(
        in: screenshot, around: app.buttons["miniwhisper.onboarding.try-it.skip"],
      ),
      0, "Skip is painted as focused after the page swapped underneath it",
    )
  }

  // MARK: Recording

  @MainActor func testShortcutRecordingContract() {
    let app = launch("onboarding-shortcut")
    defer { terminate(app) }

    let keycap = app.buttons["miniwhisper.onboarding.shortcut.binding"]
    let ring = app.staticTexts["miniwhisper.onboarding.shortcut.binding.state"]
    let caption = app.staticTexts["miniwhisper.onboarding.shortcut.caption"]
    let continueButton = app.buttons["miniwhisper.onboarding.shortcut.continue"]
    XCTAssertTrue(keycap.waitForExistence(timeout: 5))
    keycap.click()
    assertValue("Recording…", of: keycap)
    assertValue("Ring off", of: ring)
    assertValue("Record your shortcut", of: caption)
    XCTAssertFalse(continueButton.isEnabled)

    app.typeKey(.escape, modifierFlags: [])
    assertValue("⌥ Opt →", of: keycap)
    assertValue("Click the shortcut to change", of: caption)
    XCTAssertTrue(continueButton.isEnabled)
  }

  @MainActor func testFocusedKeycapRecordsOnReturnAndSpace() {
    for key: XCUIKeyboardKey in [.return, .space] {
      let app = launch("onboarding-shortcut")
      let keycap = app.buttons["miniwhisper.onboarding.shortcut.binding"]
      XCTAssertTrue(keycap.waitForExistence(timeout: 5))

      app.typeKey(.tab, modifierFlags: [])
      assertValue("Ring on", of: app.staticTexts["miniwhisper.onboarding.shortcut.binding.state"])
      app.typeKey(key, modifierFlags: [])
      assertValue("Recording…", of: keycap)

      app.typeKey(.escape, modifierFlags: [])
      terminate(app)
    }
  }

  /// Return belongs to Continue until the keycap is focused, so the shortcut step never taxes
  /// someone who is just pressing Return through the whole flow.
  @MainActor func testUnfocusedReturnSkipsPastTheKeycap() {
    let app = launch("onboarding-shortcut")
    defer { terminate(app) }

    let keycap = app.buttons["miniwhisper.onboarding.shortcut.binding"]
    XCTAssertTrue(keycap.waitForExistence(timeout: 5))
    app.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(app.groups["miniwhisper.onboarding.model"].waitForExistence(timeout: 2))
  }

  /// A recording owns the keyboard outright, so the rail stops being somewhere to go until it is
  /// over — otherwise the next chord lands on a page that has already left.
  @MainActor func testRailIsFrozenWhileRecording() {
    let app = launch("onboarding-shortcut")
    defer { terminate(app) }

    let keycap = app.buttons["miniwhisper.onboarding.shortcut.binding"]
    let rail = app.buttons["miniwhisper.onboarding.rail.permissions"]
    XCTAssertTrue(keycap.waitForExistence(timeout: 5))
    XCTAssertTrue(rail.isEnabled)

    keycap.click()
    assertValue("Recording…", of: keycap)
    XCTAssertFalse(rail.isEnabled)
    XCTAssertFalse(app.buttons["miniwhisper.onboarding.shortcut.continue"].isEnabled)

    app.typeKey(.escape, modifierFlags: [])
    assertValue("⌥ Opt →", of: keycap)
    XCTAssertTrue(rail.isEnabled)
  }

  // MARK: Private

  @MainActor private func assertOnlyWindowHasKeyboardFocus(
    in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line,
  ) {
    let focusedElements = app.descendants(matching: .any)
      .matching(NSPredicate(format: "hasKeyboardFocus == true"))
      .allElementsBoundByIndex
    XCTAssertEqual(
      focusedElements.map(\.identifier), ["miniwhisper.onboarding.window"],
      "Unexpected focused elements: \(focusedElements.map(\.debugDescription))",
      file: file,
      line: line,
    )
  }
}
