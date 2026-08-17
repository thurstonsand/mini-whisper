import XCTest

/// Onboarding's keyboard grammar, asserted the way a user meets it: Return does the visible step's
/// one job, and Tab visits only the controls that step actually offers.
final class OnboardingKeyboardUITests: MiniWhisperUITestCase, SurfaceTagged {
  // MARK: Internal

  static let surfaces: Set<Surface> = [.onboarding]

  @MainActor func testSingleActionPageKeyboardLaws() {
    // Each page's single action owns the tab order; Return then proves the action does what its
    // page promises. The Return consequences differ, so each page carries its own.
    let pages: [(scene: String, identifier: String,
                 pressReturn: @MainActor (XCUIApplication, XCUIElement) -> Void)] = [
      ("onboarding-welcome", "miniwhisper.onboarding.download-model", { app, _ in
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(
          app.groups["miniwhisper.onboarding.permissions"].awaitExistence(timeout: 2),
        )
      }),
      (
        "onboarding-permissions-microphone",
        "miniwhisper.onboarding.permission.microphone.action",
        { app, action in
          XCTAssertEqual(action.label, "Grant Microphone")
          app.typeKey(.return, modifierFlags: [])
          let accessibility = app.buttons[
            "miniwhisper.onboarding.permission.accessibility.action",
          ]
          XCTAssertTrue(accessibility.awaitExistence(timeout: 2))
          XCTAssertEqual(accessibility.label, "Grant Accessibility")
          app.typeKey(.return, modifierFlags: [])
          XCTAssertTrue(app.groups["miniwhisper.onboarding.shortcut"].awaitExistence(timeout: 2))
        },
      ),
      (
        "onboarding-permissions-accessibility-settings",
        "miniwhisper.onboarding.permission.accessibility.action",
        { app, action in
          XCTAssertEqual(action.label, "Open Accessibility Settings")
          app.typeKey(.return, modifierFlags: [])
          XCTAssertTrue(
            app.descendants(matching: .any)["miniwhisper.onboarding.failure"]
              .awaitExistence(timeout: 2),
          )
        },
      ),
      ("onboarding-model-actionable", "miniwhisper.onboarding.model.retry", { app, _ in
        let failure = app.descendants(matching: .any)["miniwhisper.onboarding.failure"]
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(failure.awaitNonExistence())
      }),
      ("onboarding-ready", "miniwhisper.onboarding.ready.finish", { app, _ in
        let ready = app.groups["miniwhisper.onboarding.ready"]
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(ready.awaitNonExistence())
      }),
    ]

    let app = launch(pages[0].scene)
    defer { terminate(app) }

    for (index, page) in pages.enumerated() {
      if index > 0 {
        presentScene(page.scene)
      }
      let action = app.buttons[page.identifier]
      XCTAssertTrue(action.awaitExistence(timeout: 5), page.scene)

      for modifiers: XCUIElement.KeyModifierFlags in [[], [], [.shift], [.shift]] {
        app.typeKey(.tab, modifierFlags: modifiers)
        assertKeyboardFocus(on: action)
      }

      page.pressReturn(app, action)
    }
  }

  /// macOS lists an app under Privacy & Security > Microphone only once the app has asked, and
  /// that list has no way to add one by hand. Taking Grant away before it was pressed therefore
  /// strands the user in front of a pane their app is not in.
  @MainActor func testLeavingAndReturningToPermissionsKeepsTheGrantButton() {
    let app = launch("onboarding-permissions-microphone")
    defer { terminate(app) }

    let action = app.buttons["miniwhisper.onboarding.permission.microphone.action"]
    XCTAssertTrue(action.awaitExistence(timeout: 5))
    XCTAssertEqual(action.label, "Grant Microphone")

    app.buttons["miniwhisper.onboarding.rail.try-it"].click()
    XCTAssertTrue(
      app.buttons["miniwhisper.onboarding.rail.permissions"].awaitExistence(timeout: 2),
    )
    app.buttons["miniwhisper.onboarding.rail.permissions"].click()

    XCTAssertTrue(action.awaitExistence(timeout: 2))
    XCTAssertEqual(action.label, "Grant Microphone")
    assertValue(
      "Required", of: app.staticTexts["miniwhisper.onboarding.permission.microphone.status"],
    )
  }

  @MainActor func testOpenSettingsReplacesStatusWithoutReflowingPermissionCopy() {
    let app = launch("onboarding-permissions-accessibility")
    defer { terminate(app) }

    let explanation = app.staticTexts["miniwhisper.onboarding.permission.accessibility"]
    XCTAssertTrue(explanation.awaitExistence(timeout: 5))
    let grantHeight = explanation.frame.height

    presentScene("onboarding-permissions-accessibility-settings")
    XCTAssertTrue(
      app.buttons["miniwhisper.onboarding.permission.accessibility.action"]
        .awaitExistence(timeout: 2),
    )
    XCTAssertTrue(
      app.staticTexts["miniwhisper.onboarding.permission.accessibility.status"]
        .awaitNonExistence(timeout: 2),
    )
    XCTAssertEqual(explanation.frame.height, grantHeight)
  }

  @MainActor func testModelProgressHasNoTabStopsAndCanBeAbandoned() {
    let app = launch("onboarding-model")
    defer { terminate(app) }

    XCTAssertTrue(app.groups["miniwhisper.onboarding.model"].awaitExistence(timeout: 5))
    let railButtons = ["permissions", "shortcut", "model", "try-it"].map {
      app.buttons["miniwhisper.onboarding.rail.\($0)"]
    }
    XCTAssertTrue(railButtons.allSatisfy { $0.awaitExistence(timeout: 2) })
    let railRowHeights = railButtons.map(\.frame.height)
    XCTAssertLessThan(
      railRowHeights.max() ?? 0, 20,
      "Every rail label must remain a single line",
    )
    for modifiers: XCUIElement.KeyModifierFlags in [[], [], [.shift], [.shift]] {
      app.typeKey(.tab, modifierFlags: modifiers)
      assertOnlyWindowHasKeyboardFocus(in: app)
    }

    app.buttons["miniwhisper.onboarding.rail.permissions"].click()
    XCTAssertTrue(app.groups["miniwhisper.onboarding.permissions"].awaitExistence(timeout: 2))
    for modifiers: XCUIElement.KeyModifierFlags in [[], [.shift]] {
      app.typeKey(.tab, modifierFlags: modifiers)
      assertOnlyWindowHasKeyboardFocus(in: app)
    }

    let skip = app.buttons["miniwhisper.onboarding.try-it.skip"]
    app.buttons["miniwhisper.onboarding.rail.try-it"].click()
    XCTAssertTrue(skip.awaitExistence(timeout: 2))
    XCTAssertFalse(app.tryItEditor.exists)

    skip.click()
    XCTAssertTrue(app.staticTexts["miniwhisper.menu.status-item"].awaitNonExistence(timeout: 3))
    XCTAssertFalse(app.buttons["miniwhisper.onboarding.rail.try-it"].exists)
  }

  @MainActor func testRevisitedReadyModelOffersKeyboardContinue() {
    let app = launch("onboarding-model")
    defer { terminate(app) }

    let continueButton = app.buttons["miniwhisper.onboarding.model.continue"]
    XCTAssertTrue(app.groups["miniwhisper.onboarding.model"].awaitExistence(timeout: 5))
    XCTAssertFalse(continueButton.exists)

    postAgentMutation("model-ready", value: "")
    XCTAssertTrue(continueButton.awaitExistence(timeout: 2))
    app.typeKey(.tab, modifierFlags: [])
    assertKeyboardFocus(on: continueButton)
    app.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(app.tryItEditor.awaitExistence(timeout: 2))
  }

  @MainActor func testShortcutKeyboardLaws() {
    let app = launch("onboarding-shortcut")
    defer { terminate(app) }

    let keycap = app.buttons["miniwhisper.onboarding.shortcut.binding"]
    let ring = app.staticTexts["miniwhisper.onboarding.shortcut.binding.state"]
    let continueButton = app.buttons["miniwhisper.onboarding.shortcut.continue"]
    XCTAssertTrue(keycap.awaitExistence(timeout: 5))
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

    app.typeKey(.tab, modifierFlags: [])
    assertValue("Ring on", of: ring)
    resetShortcutFocus(app)
    let roundTripScreenshot = app.screenshot()
    recordScreenshot("shortcut-rail-round-trip", screenshot: roundTripScreenshot)
    XCTAssertEqual(
      focusRingPixelCount(in: roundTripScreenshot, around: keycap), 0,
      "The keycap kept its ring across a rail round trip",
    )

    let caption = app.staticTexts["miniwhisper.onboarding.shortcut.caption"]
    keycap.click()
    assertValue("Recording…", of: keycap)
    assertValue("Ring off", of: ring)
    assertValue("Record your shortcut", of: caption)
    XCTAssertFalse(continueButton.isEnabled)
    app.typeKey(.escape, modifierFlags: [])
    assertValue("⌥ Opt →", of: keycap)
    assertValue("Click the shortcut to change", of: caption)
    XCTAssertTrue(continueButton.isEnabled)

    for key: XCUIKeyboardKey in [.return, .space] {
      resetShortcutFocus(app)
      app.typeKey(.tab, modifierFlags: [])
      assertValue("Ring on", of: ring)
      app.typeKey(key, modifierFlags: [])
      assertValue("Recording…", of: keycap)
      app.typeKey(.escape, modifierFlags: [])
    }

    resetShortcutFocus(app)
    let rail = app.buttons["miniwhisper.onboarding.rail.permissions"]
    XCTAssertTrue(rail.isEnabled)
    keycap.click()
    assertValue("Recording…", of: keycap)
    XCTAssertFalse(rail.isEnabled)
    XCTAssertFalse(continueButton.isEnabled)
    app.typeKey(.escape, modifierFlags: [])
    assertValue("⌥ Opt →", of: keycap)
    XCTAssertTrue(rail.isEnabled)
  }

  @MainActor func testTryItTabCyclesOnlyBetweenEditorAndSkip() {
    let app = launch("onboarding-try-it")
    defer { terminate(app) }

    let editor = app.tryItEditor
    let skip = app.buttons["miniwhisper.onboarding.try-it.skip"]
    let skipRing = app.staticTexts["miniwhisper.onboarding.try-it.skip.state"]
    XCTAssertTrue(editor.awaitExistence(timeout: 5))
    XCTAssertEqual(
      editor.placeholderValue,
      "“A future is not given to you. It is something you must take for yourself.” — Pod 042",
      "The try-it field does not offer the line the page asks the user to read",
    )
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

    app.typeKey(.tab, modifierFlags: [])
    assertKeyboardFocus(on: skip)
    app.buttons["miniwhisper.onboarding.rail.permissions"].click()
    XCTAssertTrue(app.groups["miniwhisper.onboarding.permissions"].awaitExistence(timeout: 2))
    app.buttons["miniwhisper.onboarding.rail.try-it"].click()
    XCTAssertTrue(editor.awaitExistence(timeout: 2))

    assertKeyboardFocus(on: editor)
    assertValue("Ring off", of: skipRing)
    let roundTripScreenshot = app.screenshot()
    recordScreenshot("try-it-rail-round-trip", screenshot: roundTripScreenshot)
    XCTAssertEqual(
      focusRingPixelCount(in: roundTripScreenshot, around: skip), 0,
      "Skip kept its ring across a rail round trip",
    )
  }

  /// Entry focus is not only a launch-time story: the model finishing behind the user's back
  /// swaps the page under them, and the caret has to land in the editor there too.
  @MainActor func testTryItTakesFocusWhenTheModelFinishesBehindIt() {
    let app = launch("onboarding-shortcut")
    defer { terminate(app) }

    XCTAssertTrue(
      app.buttons["miniwhisper.onboarding.shortcut.continue"].awaitExistence(timeout: 5),
    )
    app.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(app.groups["miniwhisper.onboarding.model"].awaitExistence(timeout: 2))

    postAgentMutation("model-ready", value: "now")
    let editor = app.tryItEditor
    XCTAssertTrue(editor.awaitExistence(timeout: 3))
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

  // MARK: Private

  @MainActor private func resetShortcutFocus(_ app: XCUIApplication) {
    app.buttons["miniwhisper.onboarding.rail.permissions"].click()
    XCTAssertTrue(app.groups["miniwhisper.onboarding.permissions"].awaitExistence(timeout: 2))
    app.buttons["miniwhisper.onboarding.rail.shortcut"].click()
    XCTAssertTrue(
      app.buttons["miniwhisper.onboarding.shortcut.binding"].awaitExistence(timeout: 2),
    )
    assertValue(
      "Ring off", of: app.staticTexts["miniwhisper.onboarding.shortcut.binding.state"],
    )
  }

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
