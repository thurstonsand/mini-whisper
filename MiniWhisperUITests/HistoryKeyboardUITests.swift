import XCTest

/// The history pane's keyboard and pointer grammar. The cursor is the subject of nearly every
/// claim here, so the laws run in the order written and each opens by stating where it expects to
/// find the cursor the previous law left.
final class HistoryKeyboardUITests: MiniWhisperUITestCase, SurfaceTagged {
  // MARK: Internal

  static let surfaces: Set<Surface> = [.history]

  @MainActor func testFirstRowsKeepTheirHeightWhenInsertedIntoOpenPane() {
    let app = launch("settings")
    defer { terminate(app) }

    let history = app.staticTexts["miniwhisper.settings.sidebar.history"]
    XCTAssertTrue(history.awaitHittable(timeout: 5))
    history.click()
    XCTAssertTrue(app.staticTexts["No History"].awaitExistence(timeout: 2))

    postAgentMutation("history-first-entries", value: "")
    waitForAgentResult("history:first-entries")
    let first = historyRow(app, id: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
    let second = historyRow(app, id: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")
    XCTAssertTrue(first.awaitExistence(timeout: 2))
    XCTAssertTrue(second.awaitExistence(timeout: 2))
    let pitch = abs(first.frame.midY - second.frame.midY)
    XCTAssertGreaterThanOrEqual(pitch, 30, "History row pitch was \(pitch)pt")
  }

  @MainActor func testHistoryKeyboardLaws() {
    let firstID = "11111111-1111-1111-1111-111111111111"
    let secondID = "22222222-2222-2222-2222-222222222222"
    let thirdID = "00000000-0000-0000-0000-000000000003"

    assertLaws(on: "settings-history", [
      Law("Entering from the sidebar paints the first cursor") { app in
        try require(self.historyRow(app, id: firstID).awaitExistence(timeout: 5))
        app.typeText("h")
        self.assertValue("Focused", of: app.outlines["miniwhisper.settings.sidebar"])
        app.typeText("l")
        self.assertValue("Not focused", of: app.outlines["miniwhisper.settings.sidebar"])
        self.assertValue(
          "Grey on; Cursor on; Copied off", of: self.historyRowState(app, id: firstID),
        )
      },

      Law("Movement keeps exactly one grey row") { app in
        try require(self.awaitGrey(app, id: firstID), "The cursor is not on the first row")
        app.typeText("j")
        self.assertSingleGreyHistoryRow(app, id: secondID)
        app.typeText("k")
        self.assertSingleGreyHistoryRow(app, id: firstID)
      },

      Law("Copying keeps the cursor") { app in
        try require(self.awaitGrey(app, id: firstID), "The cursor is not on the first row")
        app.typeText("l")
        try require(self.copiedToast(app, id: firstID).awaitExistence(timeout: 2))
        XCTAssertTrue(
          self.accessibilityValue(self.historyRowState(app, id: firstID)).contains("Cursor on"),
        )
      },

      Law("A round trip restores the same cursor") { app in
        app.typeText("jh")
        self.assertNoGreyHistoryRow(app, "The sidebar took the keys and a row kept its grey:")
        app.typeText("l")
        self.assertSingleGreyHistoryRow(app, id: secondID)
      },

      Law("A parked pointer cannot steal keyboard grey") { app in
        app.typeText("k")
        try require(self.awaitGrey(app, id: firstID), "The cursor is not on the first row")
        self.historyRow(app, id: firstID).hover()
        app.typeText("jj")
        self.assertSingleGreyHistoryRow(app, id: thirdID)
      },

      Law("The sidebar walks destinations and the cursor survives the trip") { app in
        try require(self.awaitGrey(app, id: thirdID), "The cursor is not on the third row")
        app.typeText("hj")
        let placeholder = app.descendants(matching: .any)["miniwhisper.settings.placeholder"]
        try require(placeholder.awaitExistence(timeout: 2))
        XCTAssertTrue(placeholder.label.hasPrefix("Model"))

        app.typeText("k")
        try require(self.historyRow(app, id: firstID).awaitExistence(timeout: 2))
        app.typeText("ll")
        XCTAssertTrue(self.copiedToast(app, id: thirdID).awaitExistence(timeout: 2))
      },

      Law("Return hands the keys back with the filter intact") { app in
        app.typeText("/")
        let search = app.searchFields.firstMatch
        try require(search.awaitExistence(timeout: 2))
        app.typeText("keyboard")
        try require(self.historyRow(app, id: firstID).awaitNonExistence())
        self.assertNoGreyHistoryRow(
          app, "The search field holds the keys and a row kept its grey:",
        )

        app.typeKey(.return, modifierFlags: [])
        app.typeText("l")
        XCTAssertTrue(self.copiedToast(app, id: thirdID).awaitExistence(timeout: 2))
      },

      Law("Escape abandons the query and hands the keys back") { app in
        app.typeText("/")
        app.typeText("xyzzy")
        app.typeKey(.escape, modifierFlags: [])
        try require(self.historyRow(app, id: firstID).awaitExistence(timeout: 2))
        self.assertValue("", of: app.searchFields.firstMatch)

        // The cursor stayed where the filtered list left it, so k reaches the row above it.
        app.typeText("kl")
        XCTAssertTrue(self.copiedToast(app, id: secondID).awaitExistence(timeout: 2))
      },

      Law("The cursor stays on screen after visiting the sidebar") { app in
        app.typeText("k")
        try require(self.awaitGrey(app, id: firstID), "The cursor is not on the first row")
        let deepID = "00000000-0000-0000-0000-000000000028"
        let cursor = self.historyRow(app, id: deepID)

        app.typeText(String(repeating: "j", count: 27))
        try require(cursor.awaitExistence(timeout: 5))
        self.assertSingleGreyHistoryRow(app, id: deepID)
        XCTAssertTrue(cursor.isHittable)

        app.typeText("hkj")
        XCTAssertTrue(cursor.isHittable, "The cursor came back off-screen.")

        app.typeText("l")
        self.assertSingleGreyHistoryRow(app, id: deepID)
        XCTAssertTrue(cursor.isHittable)
      },
    ])
  }

  @MainActor func testHistorySettingsInteractions() throws {
    let app = launch("settings-history")
    defer { terminate(app) }

    let firstID = "11111111-1111-1111-1111-111111111111"
    let secondID = "22222222-2222-2222-2222-222222222222"
    let firstRow = historyRow(app, id: firstID)
    let secondRow = historyRow(app, id: secondID)
    XCTAssertTrue(firstRow.awaitExistence(timeout: 5))
    XCTAssertTrue(secondRow.exists)

    firstRow.click()
    XCTAssertTrue(copiedToast(app, id: firstID).awaitExistence(timeout: 2))

    let storage = app.buttons["miniwhisper.history.storage"]
    XCTAssertTrue(storage.awaitHittable())
    storage.click()
    let popover = app.descendants(matching: .any)["miniwhisper.history.storage.popover"]
    XCTAssertTrue(popover.awaitExistence(timeout: 2))
    app.typeKey(.escape, modifierFlags: [])
    XCTAssertTrue(popover.awaitNonExistence(), "Escape did not dismiss the storage popover")

    secondRow.rightClick()
    let deleteItems = app.menuItems.matching(identifier: "Delete")
    XCTAssertTrue(deleteItems.firstMatch.awaitExistence(timeout: 2))
    let delete = try XCTUnwrap(
      deleteItems.allElementsBoundByIndex.first(where: \.isHittable),
    )
    delete.click()
    XCTAssertTrue(secondRow.awaitNonExistence())
  }

  // MARK: Private

  private func historyRow(_ app: XCUIApplication, id: String) -> XCUIElement {
    app.descendants(matching: .any)["miniwhisper.history.row.\(id)"]
  }

  private func historyRowState(_ app: XCUIApplication, id: String) -> XCUIElement {
    app.staticTexts["miniwhisper.history.row.\(id).state"]
  }

  private func copiedToast(_ app: XCUIApplication, id: String) -> XCUIElement {
    app.descendants(matching: .any)["miniwhisper.history.copied.\(id)"]
  }

  /// Reading thirty-two row states one property at a time costs a remote query apiece. One
  /// snapshot of the tree costs less than a single one of those queries and answers for all of
  /// them, which is what makes asking about every row on every keystroke affordable.
  @MainActor private func historyRowStates(_ app: XCUIApplication) -> [String: String] {
    guard let tree = try? app.snapshot() else {
      XCTFail("Could not snapshot the application")
      return [:]
    }
    return accessibilitySnapshots(tree)
      .filter { $0.key.hasPrefix("miniwhisper.history.row.") && $0.key.hasSuffix(".state") }
      .compactMapValues { snapshots in snapshots.last.map(accessibilityValue) }
  }

  @MainActor private func assertNoGreyHistoryRow(
    _ app: XCUIApplication, _ message: String, file: StaticString = #filePath, line: UInt = #line,
  ) {
    var greys: [String] = []
    let settled = poll {
      greys = self.greyHistoryRows(app)
      return greys.isEmpty
    }
    XCTAssertTrue(settled, "\(message) \(greys)", file: file, line: line)
  }

  /// A keystroke is delivered before it is drawn, so every claim about the grey row is polled
  /// until it holds and only then reported. Sampling the instant `typeText` returns asks the
  /// window a question it has not finished answering.
  @MainActor private func greyHistoryRows(_ app: XCUIApplication) -> [String] {
    historyRowStates(app).filter { $0.value.contains("Grey on") }.keys.sorted()
  }

  @MainActor private func awaitGrey(_ app: XCUIApplication, id: String) -> Bool {
    poll { self.greyHistoryRows(app) == ["miniwhisper.history.row.\(id).state"] }
  }

  @MainActor private func assertSingleGreyHistoryRow(
    _ app: XCUIApplication, id: String, file: StaticString = #filePath, line: UInt = #line,
  ) {
    let expected = "miniwhisper.history.row.\(id).state"
    var states: [String: String] = [:]
    let settled = poll {
      states = self.historyRowStates(app)
      return states.filter { $0.value.contains("Grey on") }.keys.sorted() == [expected]
        && states[expected, default: ""].contains("Cursor on")
    }
    XCTAssertTrue(
      settled, "The cursor is not alone on \(id): \(greyHistoryRows(app))",
      file: file, line: line,
    )
  }
}
