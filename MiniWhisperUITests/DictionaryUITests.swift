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

    app.typeText("l")
    assertValue(
      "Grey on; Cursor on",
      of: app.staticTexts[
        "miniwhisper.dictionary.row.vocabulary.miniwhisper.state",
      ],
    )
    app.typeText("j")
    assertValue(
      "Grey on; Cursor on",
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
    XCTAssertTrue(app.staticTexts["Dictionary could not be saved"].exists)
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
