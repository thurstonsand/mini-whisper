import AppKit
import XCTest

final class DictionaryUITests: XCTestCase {
  // MARK: Internal

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor func testDictionaryPaneKeyboardAndEditing() {
    let app = launch("settings-dictionary")
    defer { terminate(app) }

    let vocabulary = app.descendants(matching: .any)[
      "miniwhisper.dictionary.row.vocabulary.miniwhisper",
    ]
    let correction = app.descendants(matching: .any)[
      "miniwhisper.dictionary.row.correction.mini-whisperer",
    ]
    XCTAssertTrue(vocabulary.awaitExistence(timeout: 5))
    XCTAssertTrue(correction.exists)

    let improveRecognition = app.checkBoxes["miniwhisper.dictionary.improve-recognition"]
    XCTAssertTrue(improveRecognition.awaitHittable(timeout: 2))
    improveRecognition.click()
    assertValue(
      "Grey off; Cursor off; Emphasis reduced",
      of: app.staticTexts[
        "miniwhisper.dictionary.row.vocabulary.miniwhisper.state",
      ],
    )
    assertValue(
      "Grey off; Cursor off; Emphasis normal",
      of: app.staticTexts[
        "miniwhisper.dictionary.row.correction.mini-whisperer.state",
      ],
    )

    app.typeText("l")
    assertValue(
      "Grey on; Cursor on; Emphasis reduced",
      of: app.staticTexts[
        "miniwhisper.dictionary.row.vocabulary.miniwhisper.state",
      ],
    )
    app.typeText("j")
    assertValue(
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
    XCTAssertTrue(sheet.awaitExistence(timeout: 2))
    let editHeadline = app.staticTexts["Edit Entry"]
    XCTAssertTrue(editHeadline.awaitExistence(timeout: 2))
    recordScreenshot("recognition-off-sheet", screenshot: app.screenshot())
    XCTAssertTrue(sheet.buttons["Delete"].exists)
    assertValue("mini whisperer", of: app.textFields["miniwhisper.dictionary.misspelling"])
    assertValue("MiniWhisper", of: app.textFields["miniwhisper.dictionary.text"])
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(sheet.awaitNonExistence())

    let add = app.buttons["miniwhisper.dictionary.add"]
    XCTAssertTrue(add.awaitHittable())
    add.click()
    XCTAssertTrue(sheet.awaitExistence(timeout: 2))
    XCTAssertTrue(app.staticTexts["Add Entry"].exists)
    let save = app.buttons["miniwhisper.dictionary.save"]
    XCTAssertTrue(save.awaitExistence(timeout: 2))
    XCTAssertFalse(save.isEnabled)
    let text = app.textFields["miniwhisper.dictionary.text"]
    text.click()
    text.typeText("TCA")
    XCTAssertTrue(poll { save.isEnabled })
    XCTAssertTrue(save.isEnabled)
    text.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(app.descendants(matching: .any)["miniwhisper.dictionary.row.vocabulary.tca"]
      .awaitExistence(timeout: 2))
    XCTAssertTrue(sheet.awaitNonExistence())

    app.typeText("n")
    XCTAssertTrue(sheet.awaitExistence(timeout: 2))
    XCTAssertTrue(app.staticTexts["Add Entry"].exists)
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(sheet.awaitNonExistence())

    app.typeKey(.delete, modifierFlags: [])
    XCTAssertTrue(correction.awaitNonExistence())
  }

  @MainActor func testQuickAddOwnsNativeMenuItemInteractionBand() {
    let app = launch("settings-dictionary")
    defer { terminate(app) }

    openStatusMenu(app)
    let aboutItem = app.menuItems["miniwhisper.menu.about"]
    let quickAddItem = app.descendants(matching: .any)["miniwhisper.menu.quick-add"]
    XCTAssertTrue(aboutItem.awaitHittable(timeout: 2))
    XCTAssertTrue(quickAddItem.exists)
    let nativeFrame = aboutItem.frame
    let quickAddFrame = quickAddItem.frame
    print("ITEM FRAMES native=\(nativeFrame) quick-add=\(quickAddFrame)")
    app.typeKey(.escape, modifierFlags: [])

    let horizontalInsets = stride(from: CGFloat(0.5), through: 30, by: 0.5)
    let verticalInsets = stride(
      from: CGFloat(0.5), through: nativeFrame.height / 2, by: 0.5,
    )
    let candidates: [(String, [CGPoint])] = [
      (
        "left edge",
        horizontalInsets.map { CGPoint(x: $0, y: nativeFrame.height / 2) },
      ),
      (
        "right edge",
        horizontalInsets.map { CGPoint(x: nativeFrame.width - $0, y: nativeFrame.height / 2) },
      ),
      (
        "top edge",
        verticalInsets.map { CGPoint(x: nativeFrame.width / 2, y: $0) },
      ),
      (
        "bottom edge",
        verticalInsets.map { CGPoint(x: nativeFrame.width / 2, y: nativeFrame.height - $0) },
      ),
    ]
    var probes: [(String, CGPoint)] = []

    for (name, offsets) in candidates {
      let offset = offsets.first { offset in
        openStatusMenu(app)
        click(
          at: CGPoint(x: nativeFrame.minX + offset.x, y: nativeFrame.minY + offset.y), in: app,
        )
        let aboutWindow = app.windows["miniwhisper.about.window"]
        let activated = aboutWindow.awaitExistence(timeout: 0.3)
        app.typeKey(.escape, modifierFlags: [])
        if activated {
          XCTAssertTrue(aboutWindow.awaitNonExistence(timeout: 1))
        }
        return activated
      }
      XCTAssertNotNil(offset, "Could not find the native \(name)")
      if let offset {
        probes.append((name, offset))
        print(
          "NATIVE BAND \(name): absolute=(\(nativeFrame.minX + offset.x), \(nativeFrame.minY + offset.y)) offset=(\(offset.x), \(offset.y))",
        )
      }
    }

    for (name, offset) in probes {
      openStatusMenu(app)
      click(
        at: CGPoint(x: quickAddFrame.minX + offset.x, y: quickAddFrame.minY + offset.y), in: app,
      )
      let word = app.textFields["miniwhisper.menu.quick-add.word"]
      XCTAssertTrue(word.awaitExistence(timeout: 1), "Quick Add did not own the native \(name)")
      word.typeKey(.escape, modifierFlags: [])
    }

    openStatusMenu(app)
    for (name, offset) in probes {
      hover(
        at: CGPoint(x: quickAddFrame.minX + offset.x, y: quickAddFrame.minY + offset.y), in: app,
      )
      let hoverState = app.buttons["miniwhisper.menu.quick-add.header"]
      XCTAssertTrue(hoverState.awaitExistence(timeout: 1))
      XCTAssertTrue(
        poll { self.accessibilityValue(hoverState).hasPrefix("Hover on") },
        "Quick Add did not hover at the native \(name): \(accessibilityValue(hoverState))",
      )
      if name == "right edge" {
        recordScreenshot("quick-add-native-band-hover", screenshot: app.screenshot())
      }
    }
    app.typeKey(.escape, modifierFlags: [])
  }

  /// The badge and the switch share a row, so the one thing worth pinning is that they never
  /// share a click: opening the explanation must not silently change the setting.
  @MainActor func testRecognitionInfoBadgeExplainsWithoutTogglingTheSetting() {
    let app = launch("settings-dictionary")
    defer { terminate(app) }

    let improveRecognition = app.checkBoxes["miniwhisper.dictionary.improve-recognition"]
    XCTAssertTrue(improveRecognition.awaitHittable(timeout: 5))
    let wasEnabled = improveRecognition.value as? Int

    let badge = app.buttons["miniwhisper.dictionary.improve-recognition.info"]
    XCTAssertTrue(badge.awaitHittable(timeout: 2))
    badge.click()

    let explanation = app.descendants(matching: .any)[
      "miniwhisper.dictionary.improve-recognition.popover",
    ]
    XCTAssertTrue(explanation.awaitExistence(timeout: 2))
    assertValue(
      """
      Part of the speech transcription pipeline; turning off can speed up transcription, but will \
      no longer consider words or phrases. Replacements are always applied.
      """,
      of: explanation,
    )
    XCTAssertEqual(
      improveRecognition.value as? Int, wasEnabled,
      "Opening the explanation changed the setting",
    )
    recordScreenshot("recognition-info-popover", screenshot: app.screenshot())

    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(explanation.awaitNonExistence())

    // And the switch still answers a click of its own.
    improveRecognition.click()
    XCTAssertTrue(poll { improveRecognition.value as? Int != wasEnabled })
  }

  @MainActor func testQuickAddMarksRecognitionOffWhenCollapsedAndExpanded() {
    let app = launch("settings-dictionary")
    defer { terminate(app) }

    let improveRecognition = app.checkBoxes["miniwhisper.dictionary.improve-recognition"]
    XCTAssertTrue(improveRecognition.awaitHittable(timeout: 5))
    app.buttons["miniwhisper.dictionary.add"].click()
    let sheet = app.sheets.firstMatch
    XCTAssertTrue(sheet.awaitExistence(timeout: 2))
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(sheet.awaitNonExistence())

    let markerID = "miniwhisper.menu.quick-add.recognition-off"
    openStatusMenu(app)
    XCTAssertFalse(app.staticTexts[markerID].exists)
    app.typeKey(.escape, modifierFlags: [])

    improveRecognition.click()
    openStatusMenu(app)
    XCTAssertTrue(app.staticTexts[markerID].awaitExistence(timeout: 2))
    let quickAddItem = app.descendants(matching: .any)["miniwhisper.menu.quick-add"]
    let nativeRow = app.menuItems["miniwhisper.menu.copy-last-transcript"]
    XCTAssertEqual(quickAddItem.frame.height, nativeRow.frame.height)
    app.buttons["miniwhisper.menu.quick-add.header"].click()
    XCTAssertTrue(app.staticTexts[markerID].awaitExistence(timeout: 2))
    XCTAssertTrue(app.buttons["miniwhisper.menu.quick-add.submit"].exists)
  }

  @MainActor func testRecognitionOffMarkerScreenshotsInBothAppearances() {
    for appearance in ["dark", "light"] {
      let app = launch(
        "settings-dictionary",
        environment: ["MINIWHISPER_AGENT_APPEARANCE": appearance],
      )
      let improveRecognition = app.checkBoxes["miniwhisper.dictionary.improve-recognition"]
      XCTAssertTrue(improveRecognition.awaitHittable(timeout: 5))
      improveRecognition.click()

      openStatusMenu(app)
      let marker = app.staticTexts["miniwhisper.menu.quick-add.recognition-off"]
      XCTAssertTrue(marker.awaitExistence(timeout: 2))
      recordScreenshot("recognition-off-collapsed-\(appearance)", screenshot: app.screenshot())

      app.buttons["miniwhisper.menu.quick-add.header"].click()
      XCTAssertTrue(app.buttons["miniwhisper.menu.quick-add.submit"].awaitExistence(timeout: 2))
      XCTAssertTrue(marker.awaitExistence(timeout: 2))
      recordScreenshot("recognition-off-expanded-\(appearance)", screenshot: app.screenshot())
      terminate(app)
    }
  }

  @MainActor func testUnreadableDictionaryRefusesEditing() {
    let app = launch("settings-dictionary-unreadable")
    defer { terminate(app) }

    XCTAssertTrue(app.staticTexts["Dictionary Unavailable"].awaitExistence(timeout: 5))
  }

  @MainActor func testPanePersistenceFailureIsExplained() {
    let app = launch("settings-dictionary")
    defer { terminate(app) }
    postAgentMutation("dictionary-save-failed", value: "disk full")

    let alert = app.sheets.firstMatch
    XCTAssertTrue(alert.awaitExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["Changes could not be saved"].exists)
    XCTAssertTrue(alert.staticTexts["disk full"].exists)
    alert.buttons["OK"].click()
    XCTAssertTrue(alert.awaitNonExistence())
  }

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

  @MainActor func testQuickAddInvalidSubmitStaysOpen() {
    let app = launch("menu-healthy")
    defer { terminate(app) }

    openStatusMenu(app)
    let header = app.buttons["miniwhisper.menu.quick-add.header"]
    let word = app.textFields["miniwhisper.menu.quick-add.word"]
    XCTAssertTrue(header.awaitHittable(timeout: 2))
    XCTAssertFalse(word.exists)
    header.click()
    XCTAssertTrue(word.awaitHittable(timeout: 2))
    XCTAssertFalse(header.isEnabled)

    let add = app.buttons["miniwhisper.menu.quick-add.submit"]
    XCTAssertTrue(add.isEnabled)
    add.click()
    // XCUITest cannot inspect CAKeyframeAnimation; staying open is the observable invalid-submit
    // result.
    XCTAssertTrue(word.isHittable)
  }

  @MainActor func testQuickAddEscapeAborts() {
    let app = launch("menu-healthy")
    defer { terminate(app) }

    let word = expandQuickAdd(in: app)
    clickImmediately(word)
    word.typeText("Discard me")
    assertValue("Discard me", of: word)
    word.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(poll { !word.isHittable })
    XCTAssertFalse(quickAddPersistedVocabulary("Discard me"))
  }

  @MainActor func testQuickAddOrdinaryCloseCollapsesAndClears() {
    let app = launch("menu-healthy")
    defer { terminate(app) }

    let word = expandQuickAdd(in: app)
    word.typeText("Discard me")
    app.menuItems["miniwhisper.menu.copy-last-transcript"].click()
    XCTAssertTrue(poll { !word.isHittable })

    openStatusMenu(app)
    let header = app.buttons["miniwhisper.menu.quick-add.header"]
    XCTAssertTrue(header.awaitHittable(timeout: 2))
    XCTAssertTrue(header.isEnabled)
    XCTAssertFalse(word.exists)
    header.click()
    XCTAssertTrue(word.awaitHittable(timeout: 2))
    assertValue("", of: word)
  }

  @MainActor func testQuickAddVocabularyPersistsAndAppearsInPane() {
    let app = launch("menu-healthy")
    defer { terminate(app) }

    let word = expandQuickAdd(in: app)
    word.typeText("Ghostty")
    word.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(poll { !word.isHittable })
    XCTAssertTrue(poll { self.quickAddPersistedVocabulary("Ghostty") })

    openDictionaryPane(in: app)
    XCTAssertTrue(app.descendants(matching: .any)
      .matching(NSPredicate(format: "label == 'Ghostty'"))
      .firstMatch
      .awaitExistence(timeout: 2))
  }

  @MainActor func testQuickAddCorrectionPersistsAndAppearsInPane() {
    let app = launch("menu-healthy")
    defer { terminate(app) }

    let word = expandQuickAdd(in: app)
    word.typeText("AcmeOS")
    let disclosure = app.buttons["miniwhisper.menu.quick-add.disclosure"]
    XCTAssertTrue(disclosure.awaitHittable(timeout: 2))
    disclosure.click()
    let misspelling = app.textFields["miniwhisper.menu.quick-add.misspelling"]
    XCTAssertTrue(misspelling.awaitHittable(timeout: 2))
    XCTAssertFalse(disclosure.isEnabled)
    XCTAssertEqual(word.label, "Correct spelling")
    misspelling.typeText("acne O S")
    misspelling.typeKey(.return, modifierFlags: [])
    XCTAssertTrue(poll { !misspelling.isHittable })
    XCTAssertTrue(poll { self.quickAddPersistedCorrection("acne O S", word: "AcmeOS") })

    openDictionaryPane(in: app)
    XCTAssertTrue(app.descendants(matching: .any)
      .matching(NSPredicate(format: "label == 'acne O S, corrected to AcmeOS'"))
      .firstMatch
      .awaitExistence(timeout: 2))
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

  @MainActor private func click(at point: CGPoint, in app: XCUIApplication) {
    windowCoordinate(at: point, in: app).click()
  }

  @MainActor private func hover(at point: CGPoint, in app: XCUIApplication) {
    windowCoordinate(at: point, in: app).hover()
  }

  @MainActor private func windowCoordinate(
    at point: CGPoint, in app: XCUIApplication,
  ) -> XCUICoordinate {
    let window = app.windows["miniwhisper.settings.window"]
    return window.coordinate(withNormalizedOffset: .zero)
      .withOffset(CGVector(dx: point.x - window.frame.minX, dy: point.y - window.frame.minY))
  }

  @MainActor private func openStatusMenu(_ app: XCUIApplication) {
    let statusItem = app.statusItems["miniwhisper.menu.status-item"]
    XCTAssertTrue(statusItem.awaitHittable(timeout: 5))
    statusItem.click()
  }

  @MainActor private func expandQuickAdd(in app: XCUIApplication) -> XCUIElement {
    openStatusMenu(app)
    let header = app.buttons["miniwhisper.menu.quick-add.header"]
    XCTAssertTrue(header.awaitHittable(timeout: 2))
    header.click()
    let word = app.textFields["miniwhisper.menu.quick-add.word"]
    XCTAssertTrue(word.awaitHittable(timeout: 2))
    return word
  }

  @MainActor private func openDictionaryPane(in app: XCUIApplication) {
    openStatusMenu(app)
    let settings = app.menuItems["miniwhisper.menu.settings"]
    XCTAssertTrue(settings.awaitHittable(timeout: 2))
    settings.click()
    let dictionary = app.staticTexts["miniwhisper.settings.sidebar.dictionary"]
    XCTAssertTrue(dictionary.awaitHittable(timeout: 5))
    dictionary.click()
  }

  @MainActor private func submitQuickAdd(
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

  private func quickAddPersistedVocabulary(_ word: String) -> Bool {
    guard let data = try? Data(contentsOf: agentDictionaryFileURL),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let vocabulary = object["vocabulary"] as? [[String: Any]]
    else {
      return false
    }
    return vocabulary.contains { $0["text"] as? String == word }
  }

  private func quickAddPersistedCorrection(_ misspelling: String, word: String) -> Bool {
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
