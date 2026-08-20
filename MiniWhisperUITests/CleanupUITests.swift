import XCTest

/// The Cleanup pane's laws: what a configured pane says about itself, how the cursor walks it, and
/// what Save means. Everything is driven through the keyboard grammar, which is both the cheapest
/// way in and the thing being claimed. One launch carries the ordered group; the unconfigured pane
/// is its own launch, because an empty Keychain is the claim rather than a state to be typed into.
final class CleanupUITests: MiniWhisperUITestCase, SurfaceTagged {
  static let surfaces: Set<Surface> = [.settings]

  @MainActor func testCleanupPaneLaws() {
    assertLaws(on: "settings-cleanup", [
      Law("A configured pane shows what it will use, and the key only as evidence") { app in
        let toggle = app.switches["miniwhisper.cleanup.enabled"]
        try require(toggle.awaitExistence(timeout: 5))
        self.assertValue("1", of: toggle)
        self.assertValue(
          "https://gateway.example/v1", of: app.textFields["miniwhisper.cleanup.endpoint"],
        )
        self.assertValue("10 seconds", of: app.popUpButtons["miniwhisper.cleanup.timeout"])
        // A stored key is a prefix and dots: never the secret, never editable in place.
        self.assertValue(
          "sk-age••••••••••••", of: app.staticTexts["miniwhisper.cleanup.key.stored"],
        )
        XCTAssertTrue(app.buttons["miniwhisper.cleanup.key.replace"].exists)
        XCTAssertFalse(app.textFields["miniwhisper.cleanup.key.field"].exists)
      },

      Law("The cursor walks the pane's rows and rings its controls") { app in
        try require(app.switches["miniwhisper.cleanup.enabled"].awaitExistence(timeout: 2))
        app.typeText("l")
        self.assertValue("Bar on", of: app.staticTexts["miniwhisper.cleanup.row.enabled.state"])
        self.assertValue("Ring on", of: app.staticTexts["miniwhisper.cleanup.enabled.ring"])
        let save = app.buttons["miniwhisper.cleanup.save"]
        self.assertLabel("Save", of: save)
        self.assertEnabled(false, of: save, "Opening the pane is not an edit")

        for row in ["timeout", "endpoint", "apiKey", "model"] {
          app.typeText("j")
          self.assertValue(
            "Bar on", of: app.staticTexts["miniwhisper.cleanup.row.\(row).state"],
          )
        }
        app.typeText("kkkk")
        self.assertValue("Bar on", of: app.staticTexts["miniwhisper.cleanup.row.enabled.state"])
      },

      Law("Return opens the time limit, and Escape closes it again") { app in
        try require(app.switches["miniwhisper.cleanup.enabled"].awaitExistence(timeout: 2))
        app.typeText("j")
        self.assertValue("Bar on", of: app.staticTexts["miniwhisper.cleanup.row.timeout.state"])
        app.typeKey(.return, modifierFlags: [])
        try require(app.menuItems["30 seconds"].awaitExistence(timeout: 2))
        XCTAssertTrue(app.menuItems["5 seconds"].exists)
        app.typeKey(.escape, modifierFlags: [])
        try require(app.menuItems["30 seconds"].awaitNonExistence())
      },

      Law("A listing that answers fills the picker") { app in
        try require(app.popUpButtons["miniwhisper.cleanup.model"].awaitExistence(timeout: 2))
        // Down to the model row, right to its second target: the Load Models button.
        app.typeText("jjjl")
        self.assertValue("Bar on", of: app.staticTexts["miniwhisper.cleanup.row.model.state"])
        app.typeKey(.return, modifierFlags: [])
        self.assertValue("gpt-oss-120b", of: app.popUpButtons["miniwhisper.cleanup.model"])
        // A model that is now listed is chosen from the list, so the Custom field is gone.
        XCTAssertTrue(app.textFields["miniwhisper.cleanup.model.custom"].awaitNonExistence())

        app.typeText("h")
        app.typeKey(.return, modifierFlags: [])
        try require(app.menuItems["gpt-oss-20b"].awaitExistence(timeout: 2))
        XCTAssertTrue(app.menuItems["Custom…"].exists)
        app.typeKey(.escape, modifierFlags: [])
        try require(app.menuItems["gpt-oss-20b"].awaitNonExistence())
      },

      Law("Replace opens a field, and Save is what stores the key") { app in
        try require(app.buttons["miniwhisper.cleanup.key.replace"].awaitExistence(timeout: 2))
        app.typeText("kl")
        self.assertValue("Bar on", of: app.staticTexts["miniwhisper.cleanup.row.apiKey.state"])
        app.typeKey(.return, modifierFlags: [])
        let field = app.textFields["miniwhisper.cleanup.key.field"]
        try require(field.awaitExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["miniwhisper.cleanup.key.stored"].awaitNonExistence())

        app.typeKey(.return, modifierFlags: [])
        self.assertKeyboardFocus(on: field)
        app.typeText("sk-replaced-0123456789")
        self.assertValue("sk-replaced-0123456789", of: field)

        // Out of the field, down to the model row and along it: Save is that row's last target
        // now, and storing the key is what pressing it means. Typing the key armed the button.
        app.typeKey(.escape, modifierFlags: [])
        let save = app.buttons["miniwhisper.cleanup.save"]
        self.assertLabel("Save", of: save)
        self.assertEnabled(true, of: save, "An edited key leaves Save armed")
        app.typeText("jll")
        self.assertValue("Bar on", of: app.staticTexts["miniwhisper.cleanup.row.model.state"])
        app.typeKey(.return, modifierFlags: [])
        self.assertLabel("Saved", of: save)
        self.assertEnabled(false, of: save, "A saved section leaves nothing to save")
        self.assertValue(
          "sk-rep••••••••••••", of: app.staticTexts["miniwhisper.cleanup.key.stored"],
        )
      },

      // The button and the grammar reach the same place: a key can be pasted the moment either
      // one is pressed.
      Law("A clicked Replace hands the field the keys too") { app in
        let replace = app.buttons["miniwhisper.cleanup.key.replace"]
        try require(replace.awaitHittable(timeout: 2))
        replace.click()
        let field = app.textFields["miniwhisper.cleanup.key.field"]
        try require(field.awaitExistence(timeout: 2))
        self.assertKeyboardFocus(on: field)
        app.typeText("sk-pasted-9876543210")
        self.assertValue("sk-pasted-9876543210", of: field)
      },
    ])
  }

  @MainActor func testCleanupSaveNamesWhatIsMissing() {
    let app = launch("settings-cleanup-unconfigured")
    defer { terminate(app) }

    let result = app.staticTexts["miniwhisper.cleanup.save.result"]
    let save = app.buttons["miniwhisper.cleanup.save"]
    XCTAssertTrue(save.awaitExistence(timeout: 5))
    // Nothing is claimed until Save is pressed, and then only about what is wrong.
    XCTAssertFalse(result.exists)
    assertEnabled(false, of: save, "An unedited pane has nothing to save")

    // The address the user types is theirs until Save conforms it.
    app.typeText("ljj")
    assertValue("Bar on", of: app.staticTexts["miniwhisper.cleanup.row.endpoint.state"])
    app.typeKey(.return, modifierFlags: [])
    let endpoint = app.textFields["miniwhisper.cleanup.endpoint"]
    assertKeyboardFocus(on: endpoint)
    app.typeText("gateway.example/v1/")
    app.typeKey(.escape, modifierFlags: [])
    assertValue("gateway.example/v1/", of: endpoint)
    assertEnabled(true, of: save, "An edited address leaves Save armed")

    // Along the model row to Save. The model was never chosen, and that is what it says — under
    // the table, in red, rather than in a row of its own.
    app.typeText("jjll")
    assertValue("Bar on", of: app.staticTexts["miniwhisper.cleanup.row.model.state"])
    app.typeKey(.return, modifierFlags: [])
    assertValue("Choose a model, or enter one.", of: result)
    // Under the table, never in it: the sentence sits below the button it answers for, so no
    // row appears or disappears when Save is pressed.
    XCTAssertGreaterThan(result.frame.minY, save.frame.maxY)
    assertEnabled(true, of: save, "A failure leaves something still to save")
  }
}
