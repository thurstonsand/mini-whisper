import AppKit
import XCTest

// MARK: - DictionaryUITests

/// The dictionary's two doors — the settings pane and the menu's Quick Add — and the laws each
/// obeys. Laws run in the order written and inherit the state the previous law left, so each
/// opens by stating the ground it stands on.
final class DictionaryUITests: MiniWhisperUITestCase, SurfaceTagged {
  // MARK: Internal

  static let surfaces: Set<Surface> = [.dictionary]

  @MainActor func testDictionaryPaneLaws() {
    assertLaws(on: "settings-dictionary", [
      Law("The pane's keyboard grammar edits, adds, and deletes") { app in
        let vocabulary = app.descendants(matching: .any)[
          "miniwhisper.dictionary.row.vocabulary.miniwhisper",
        ]
        let correction = app.descendants(matching: .any)[
          "miniwhisper.dictionary.row.correction.mini-whisperer",
        ]
        try require(vocabulary.awaitExistence(timeout: 5))
        try require(correction.exists)

        let improveRecognition = app.checkBoxes["miniwhisper.dictionary.improve-recognition"]
        try require(improveRecognition.awaitHittable(timeout: 2))
        improveRecognition.click()
        self.assertValue(
          "Grey off; Cursor off; Emphasis reduced",
          of: app.staticTexts[
            "miniwhisper.dictionary.row.vocabulary.miniwhisper.state",
          ],
        )
        self.assertValue(
          "Grey off; Cursor off; Emphasis normal",
          of: app.staticTexts[
            "miniwhisper.dictionary.row.correction.mini-whisperer.state",
          ],
        )

        app.typeText("l")
        self.assertValue(
          "Grey on; Cursor on; Emphasis reduced",
          of: app.staticTexts[
            "miniwhisper.dictionary.row.vocabulary.miniwhisper.state",
          ],
        )
        app.typeText("j")
        self.assertValue(
          "Grey on; Cursor on; Emphasis normal",
          of: app.staticTexts[
            "miniwhisper.dictionary.row.correction.mini-whisperer.state",
          ],
        )
        XCTAssertTrue(
          app.buttons["miniwhisper.dictionary.row.correction.mini-whisperer.delete"].exists,
        )
        app.typeKey(.return, modifierFlags: [])
        let sheet = app.sheets.firstMatch
        try require(sheet.awaitExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Edit Entry"].awaitExistence(timeout: 2))
        self.recordScreenshot("recognition-off-sheet", screenshot: app.screenshot())
        XCTAssertTrue(sheet.buttons["Delete"].exists)
        self.assertValue("mini whisperer", of: app.textFields["miniwhisper.dictionary.misspelling"])
        self.assertValue("MiniWhisper", of: app.textFields["miniwhisper.dictionary.text"])
        app.typeKey(.escape, modifierFlags: [])
        try require(sheet.awaitNonExistence())

        let add = app.buttons["miniwhisper.dictionary.add"]
        try require(add.awaitHittable())
        add.click()
        try require(sheet.awaitExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Add Entry"].exists)
        let save = app.buttons["miniwhisper.dictionary.save"]
        try require(save.awaitExistence(timeout: 2))
        XCTAssertFalse(save.isEnabled)
        let text = app.textFields["miniwhisper.dictionary.text"]
        text.click()
        text.typeText("TCA")
        XCTAssertTrue(poll { save.isEnabled })
        text.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["miniwhisper.dictionary.row.vocabulary.tca"]
          .awaitExistence(timeout: 2))
        try require(sheet.awaitNonExistence())

        app.typeText("n")
        try require(sheet.awaitExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["Add Entry"].exists)
        app.typeKey(.escape, modifierFlags: [])
        try require(sheet.awaitNonExistence())

        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(correction.awaitNonExistence())
      },

      // The badge and the switch share a row, so the one thing worth pinning is that they never
      // share a click: opening the explanation must not silently change the setting.
      Law("The info badge explains without toggling the setting") { app in
        let improveRecognition = app.checkBoxes["miniwhisper.dictionary.improve-recognition"]
        try require(improveRecognition.awaitHittable(timeout: 2))
        let wasEnabled = improveRecognition.value as? Int

        let badge = app.buttons["miniwhisper.dictionary.improve-recognition.info"]
        try require(badge.awaitHittable(timeout: 2))
        badge.click()

        let explanation = app.descendants(matching: .any)[
          "miniwhisper.dictionary.improve-recognition.popover",
        ]
        try require(explanation.awaitExistence(timeout: 2))
        self.assertValue(
          """
          Part of the speech transcription pipeline; turning off can speed up transcription, but \
          will no longer consider words or phrases. Replacements are always applied.
          """,
          of: explanation,
        )
        XCTAssertEqual(
          improveRecognition.value as? Int, wasEnabled,
          "Opening the explanation changed the setting",
        )
        self.recordScreenshot("recognition-info-popover", screenshot: app.screenshot())

        app.typeKey(.escape, modifierFlags: [])
        try require(explanation.awaitNonExistence())

        // And the switch still answers a click of its own — which also restores recognition to
        // on, the ground the marker law expects.
        improveRecognition.click()
        XCTAssertTrue(poll { improveRecognition.value as? Int != wasEnabled })
      },

      Law("Quick Add marks recognition off, collapsed and expanded") { app in
        let improveRecognition = app.checkBoxes["miniwhisper.dictionary.improve-recognition"]
        try require(improveRecognition.awaitHittable(timeout: 2))
        try require(improveRecognition.value as? Int == 1, "Recognition is not on")
        app.buttons["miniwhisper.dictionary.add"].click()
        let sheet = app.sheets.firstMatch
        try require(sheet.awaitExistence(timeout: 2))
        app.typeKey(.escape, modifierFlags: [])
        try require(sheet.awaitNonExistence())

        let markerID = "miniwhisper.menu.quick-add.recognition-off"
        self.openStatusMenu(app)
        XCTAssertFalse(app.staticTexts[markerID].exists)
        self.closeStatusMenu(app)

        improveRecognition.click()
        self.openStatusMenu(app)
        XCTAssertTrue(app.staticTexts[markerID].awaitExistence(timeout: 2))
        let quickAddItem = app.descendants(matching: .any)["miniwhisper.menu.quick-add"]
        let nativeRow = app.menuItems["miniwhisper.menu.copy-last-transcript"]
        XCTAssertEqual(quickAddItem.frame.height, nativeRow.frame.height)
        app.buttons["miniwhisper.menu.quick-add.header"].click()
        XCTAssertTrue(app.staticTexts[markerID].awaitExistence(timeout: 2))
        XCTAssertTrue(app.buttons["miniwhisper.menu.quick-add.submit"].exists)
        self.closeStatusMenu(app)
      },

      Law("A persistence failure is explained") { app in
        self.postAgentMutation("dictionary-save-failed", value: "disk full")

        let alert = app.sheets.firstMatch
        try require(alert.awaitExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Changes could not be saved"].exists)
        XCTAssertTrue(alert.staticTexts["disk full"].exists)
        alert.buttons["OK"].click()
        XCTAssertTrue(alert.awaitNonExistence())
      },
    ])
  }

  @MainActor func testUnreadableDictionaryRefusesEditing() {
    let app = launch("settings-dictionary-unreadable")
    defer { terminate(app) }

    XCTAssertTrue(app.staticTexts["Dictionary Unavailable"].awaitExistence(timeout: 5))
  }

  // Three tests, three launches, one past bug: first rows rendered collapsed depending on
  // whether the pane was open when entries arrived, so each launch condition is its own trigger
  // and none of them can share a process.

  @MainActor func testFirstRowsKeepTheirHeightWhenQuickAddedIntoOpenPane() {
    let app = launch("menu-healthy")
    defer { terminate(app) }

    openDictionaryPane(in: app)
    submitQuickAdd(in: app, word: "asdf")
    submitQuickAdd(in: app, word: "asdf", misspelling: "example")
    assertDictionaryRowsHaveFullPitch(in: app)
  }

  @MainActor func testFirstRowsKeepTheirHeightWhenPaneOpensAfterQuickAdd() {
    let app = launch("menu-healthy")
    defer { terminate(app) }

    submitQuickAdd(in: app, word: "asdf")
    submitQuickAdd(in: app, word: "asdf", misspelling: "example")
    openDictionaryPane(in: app)
    assertDictionaryRowsHaveFullPitch(in: app)
  }

  @MainActor func testFirstRowsKeepTheirHeightFromPrepopulatedFile() {
    let app = launch("menu-healthy", dictionaryData: prepopulatedDictionary)
    defer { terminate(app) }

    openDictionaryPane(in: app)
    assertDictionaryRowsHaveFullPitch(in: app)
  }

  // MARK: Private

  private var prepopulatedDictionary: Data {
    Data(
      """
      {
        "vocabulary": [
          { "text": "asdf", "addedAt": "2026-08-16T00:00:00Z" }
        ],
        "corrections": [
          {
            "misspelling": "example",
            "text": "asdf",
            "addedAt": "2026-08-15T00:00:00Z"
          }
        ]
      }
      """.utf8,
    )
  }

  @MainActor private func assertDictionaryRowsHaveFullPitch(
    in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line,
  ) {
    let vocabulary = app.descendants(matching: .any)[
      "miniwhisper.dictionary.row.vocabulary.asdf",
    ]
    let correction = app.descendants(matching: .any)[
      "miniwhisper.dictionary.row.correction.example",
    ]
    XCTAssertTrue(vocabulary.awaitExistence(timeout: 2), file: file, line: line)
    XCTAssertTrue(correction.awaitExistence(timeout: 2), file: file, line: line)
    let pitch = abs(vocabulary.frame.midY - correction.frame.midY)
    XCTAssertGreaterThanOrEqual(
      pitch, 30, "Dictionary row pitch was \(pitch)pt", file: file, line: line,
    )
  }
}

// MARK: - QuickAddUITests

/// Quick Add lives in the status menu but writes the dictionary, so its laws belong to both
/// surfaces.
final class QuickAddUITests: MiniWhisperUITestCase, SurfaceTagged {
  static let surfaces: Set<Surface> = [.menu, .dictionary]

  @MainActor func testQuickAddLaws() {
    assertLaws(on: "menu-healthy", [
      // The native band was mapped empirically once (edge-to-edge horizontally, a hairline dead
      // margin vertically), so the standing claim is the cheap one: Quick Add answers a hover
      // and a click at every near-edge point of its own frame.
      Law("Quick Add owns its full interaction band") { app in
        self.openStatusMenu(app)
        let quickAdd = app.descendants(matching: .any)["miniwhisper.menu.quick-add"]
        let native = app.menuItems["miniwhisper.menu.about"]
        try require(quickAdd.awaitExistence(timeout: 2))
        let frame = quickAdd.frame
        let hoverState = app.buttons["miniwhisper.menu.quick-add.header"]
        try require(hoverState.awaitExistence(timeout: 2))

        let nearEdgePoints: [(String, CGVector)] = [
          ("left edge", CGVector(dx: 1, dy: frame.height / 2)),
          ("right edge", CGVector(dx: frame.width - 1, dy: frame.height / 2)),
          ("top edge", CGVector(dx: frame.width / 2, dy: 2)),
          ("bottom edge", CGVector(dx: frame.width / 2, dy: frame.height - 2)),
        ]
        for (name, offset) in nearEdgePoints {
          native.hover()
          try require(
            poll { !self.accessibilityValue(hoverState).hasPrefix("Hover on") },
            "The hover state never reset between probes",
          )
          quickAdd.coordinate(withNormalizedOffset: .zero).withOffset(offset).hover()
          XCTAssertTrue(
            poll { self.accessibilityValue(hoverState).hasPrefix("Hover on") },
            "Quick Add did not hover at its \(name): \(self.accessibilityValue(hoverState))",
          )
        }

        quickAdd.coordinate(withNormalizedOffset: .zero)
          .withOffset(CGVector(dx: frame.width / 2, dy: 2))
          .click()
        let word = app.textFields["miniwhisper.menu.quick-add.word"]
        XCTAssertTrue(word.awaitHittable(timeout: 2), "Quick Add did not accept a top-edge click")
        self.closeStatusMenu(app)
      },

      Law("An invalid submit keeps the field open") { app in
        self.openStatusMenu(app)
        let header = app.buttons["miniwhisper.menu.quick-add.header"]
        let word = app.textFields["miniwhisper.menu.quick-add.word"]
        try require(header.awaitHittable(timeout: 2))
        XCTAssertFalse(word.exists)
        header.click()
        try require(word.awaitHittable(timeout: 2))
        XCTAssertFalse(header.isEnabled)

        let add = app.buttons["miniwhisper.menu.quick-add.submit"]
        XCTAssertTrue(add.isEnabled)
        self.clickImmediately(add)
        // XCUITest cannot inspect CAKeyframeAnimation; staying open is the observable
        // invalid-submit result.
        XCTAssertTrue(word.isHittable)
        self.closeStatusMenu(app)
      },

      Law("Escape aborts and persists nothing") { app in
        let word = self.expandQuickAdd(in: app)
        self.clickImmediately(word)
        word.typeText("Discard me")
        self.assertValue("Discard me", of: word)
        word.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(poll { !word.isHittable })
        XCTAssertFalse(self.quickAddPersistedVocabulary("Discard me"))
        self.closeStatusMenu(app)
      },

      Law("An ordinary close collapses and clears") { app in
        let word = self.expandQuickAdd(in: app)
        word.typeText("Discard me")
        app.menuItems["miniwhisper.menu.copy-last-transcript"].click()
        XCTAssertTrue(poll { !word.isHittable })

        self.openStatusMenu(app)
        let header = app.buttons["miniwhisper.menu.quick-add.header"]
        try require(header.awaitHittable(timeout: 2))
        XCTAssertTrue(header.isEnabled)
        XCTAssertFalse(word.exists)
        header.click()
        try require(word.awaitHittable(timeout: 2))
        self.assertValue("", of: word)
        self.closeStatusMenu(app)
      },

      Law("A vocabulary word persists and appears in the pane") { app in
        let word = self.expandQuickAdd(in: app)
        word.typeText("Ghostty")
        word.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(poll { !word.isHittable })
        XCTAssertTrue(poll { self.quickAddPersistedVocabulary("Ghostty") })

        self.openDictionaryPane(in: app)
        XCTAssertTrue(app.descendants(matching: .any)
          .matching(NSPredicate(format: "label == 'Ghostty'"))
          .firstMatch
          .awaitExistence(timeout: 2))
      },

      Law("A correction persists and appears in the pane") { app in
        let word = self.expandQuickAdd(in: app)
        word.typeText("AcmeOS")
        let disclosure = app.buttons["miniwhisper.menu.quick-add.disclosure"]
        try require(disclosure.awaitHittable(timeout: 2))
        disclosure.click()
        let misspelling = app.textFields["miniwhisper.menu.quick-add.misspelling"]
        try require(misspelling.awaitHittable(timeout: 2))
        XCTAssertFalse(disclosure.isEnabled)
        XCTAssertEqual(word.label, "Correct spelling")
        misspelling.typeText("acne O S")
        misspelling.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(poll { !misspelling.isHittable })
        XCTAssertTrue(poll { self.quickAddPersistedCorrection("acne O S", word: "AcmeOS") })

        self.openDictionaryPane(in: app)
        XCTAssertTrue(app.descendants(matching: .any)
          .matching(NSPredicate(format: "label == 'acne O S, corrected to AcmeOS'"))
          .firstMatch
          .awaitExistence(timeout: 2))
      },
    ])
  }
}

// MARK: - Quick Add plumbing

/// Shared by every class that drives the status menu's Quick Add item.
extension MiniWhisperUITestCase {
  @MainActor func openStatusMenu(_ app: XCUIApplication) {
    let statusItem = app.statusItems["miniwhisper.menu.status-item"]
    XCTAssertTrue(statusItem.awaitHittable(timeout: 5))
    // A CGEvent click posts before the status item's tracking loop is listening, so opening the
    // menu is the one click that stays on XCUITest's synthesizer.
    statusItem.click()
  }

  /// Laws close the menu they opened so the next law's `openStatusMenu` opens rather than
  /// toggles. One escape dismisses the whole menu even from an expanded Quick Add — an escape
  /// sent after that lands nowhere and beeps — so the menu is checked before it is escaped.
  /// The probe is a native item because the quick-add views outlive the closed menu in the
  /// accessibility tree; "open" is the item being hittable, not the views existing.
  @MainActor func closeStatusMenu(_ app: XCUIApplication) {
    let nativeItem = app.menuItems["miniwhisper.menu.settings"]
    for _ in 0 ..< 3 {
      guard nativeItem.isHittable else {
        return
      }
      app.typeKey(.escape, modifierFlags: [])
      if poll(timeout: 1, until: { !nativeItem.isHittable }) {
        return
      }
    }
    XCTFail("The status menu did not close")
  }

  @MainActor func expandQuickAdd(in app: XCUIApplication) -> XCUIElement {
    openStatusMenu(app)
    let header = app.buttons["miniwhisper.menu.quick-add.header"]
    XCTAssertTrue(header.awaitHittable(timeout: 2))
    header.click()
    let word = app.textFields["miniwhisper.menu.quick-add.word"]
    XCTAssertTrue(word.awaitHittable(timeout: 2))
    return word
  }

  @MainActor func openDictionaryPane(in app: XCUIApplication) {
    openStatusMenu(app)
    let settings = app.menuItems["miniwhisper.menu.settings"]
    XCTAssertTrue(settings.awaitHittable(timeout: 2))
    settings.click()
    let dictionary = app.staticTexts["miniwhisper.settings.sidebar.dictionary"]
    XCTAssertTrue(dictionary.awaitHittable(timeout: 5))
    dictionary.click()
  }

  @MainActor func submitQuickAdd(
    in app: XCUIApplication, word: String, misspelling: String? = nil,
  ) {
    let wordField = expandQuickAdd(in: app)
    wordField.typeText(word)
    if let misspelling {
      let disclosure = app.buttons["miniwhisper.menu.quick-add.disclosure"]
      XCTAssertTrue(disclosure.awaitHittable(timeout: 2))
      disclosure.click()
      let misspellingField = app.textFields["miniwhisper.menu.quick-add.misspelling"]
      XCTAssertTrue(misspellingField.awaitHittable(timeout: 2))
      misspellingField.typeText(misspelling)
      misspellingField.typeKey(.return, modifierFlags: [])
      XCTAssertTrue(poll { !misspellingField.isHittable })
    } else {
      wordField.typeKey(.return, modifierFlags: [])
      XCTAssertTrue(poll { !wordField.isHittable })
    }
  }

  func quickAddPersistedVocabulary(_ word: String) -> Bool {
    guard let data = try? Data(contentsOf: agentDictionaryFileURL),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let vocabulary = object["vocabulary"] as? [[String: Any]]
    else {
      return false
    }
    return vocabulary.contains { $0["text"] as? String == word }
  }

  func quickAddPersistedCorrection(_ misspelling: String, word: String) -> Bool {
    guard let data = try? Data(contentsOf: agentDictionaryFileURL),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let corrections = object["corrections"] as? [[String: Any]]
    else {
      return false
    }
    return corrections.contains {
      $0["misspelling"] as? String == misspelling && $0["text"] as? String == word
    }
  }
}
