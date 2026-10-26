import XCTest

/// The Profiles pane's laws: what a saved profile says about itself, how the cursor walks it, and
/// what Edit and Save mean — every endpoint fact opens at once, and nothing is kept that the
/// endpoint did not just answer with. The scene's endpoint fails on cue: port 11435 is
/// unreachable, a key starting `sk-rejected` is refused, and `qwen3:32b` is no model it has.
final class ProfilesUITests: MiniWhisperUITestCase, SurfaceTagged {
  static let surfaces: Set<Surface> = [.settings]

  @MainActor func testProfilesPaneLaws() {
    assertLaws(on: "settings-profiles", [
      Law("A saved profile shows its values read-only, and the key only as evidence") { app in
        let toggle = app.switches["miniwhisper.profiles.enabled"]
        try require(toggle.awaitExistence(timeout: 5))
        self.assertValue("1", of: toggle)
        self.assertValue(
          "https://gateway.example/v1", of: app.staticTexts["miniwhisper.profiles.endpoint.value"],
        )
        self.assertValue(
          "sk-age••••••••••••", of: app.staticTexts["miniwhisper.profiles.apiKey.value"],
        )
        self.assertValue("gpt-oss-120b", of: app.staticTexts["miniwhisper.profiles.model.value"])
        self.assertLabel("Replace API key", of: app.buttons["miniwhisper.profiles.apiKey.edit"])
        // Nothing is editable until Edit says so.
        XCTAssertFalse(app.textFields["miniwhisper.profiles.endpoint.field"].exists)
        XCTAssertFalse(app.buttons["miniwhisper.profiles.save"].exists)
        // A factory value has nothing to reset to on Custom.
        XCTAssertFalse(app.buttons["miniwhisper.profiles.endpoint.reset"].exists)
      },

      Law("The cursor walks the pane's rows") { app in
        try require(app.switches["miniwhisper.profiles.enabled"].awaitExistence(timeout: 2))
        app.typeText("l")
        self.assertValue("Bar on", of: app.staticTexts["miniwhisper.profiles.row.profile.state"])
        app.typeText("j")
        self.assertValue("Bar on", of: app.staticTexts["miniwhisper.profiles.row.enabled.state"])
        self.assertValue("Ring on", of: app.staticTexts["miniwhisper.profiles.enabled.ring"])
        for row in ["endpoint", "apiKey", "model", "boostsVocabulary", "timeout", "instructions"] {
          app.typeText("j")
          self.assertValue(
            "Bar on", of: app.staticTexts["miniwhisper.profiles.row.\(row).state"],
          )
        }
      },

      Law("Return opens the time limit, and Escape closes it again") { app in
        self.assertValue(
          "Bar on", of: app.staticTexts["miniwhisper.profiles.row.instructions.state"],
        )
        app.typeText("k")
        self.assertValue("Bar on", of: app.staticTexts["miniwhisper.profiles.row.timeout.state"])
        app.typeKey(.return, modifierFlags: [])
        try require(app.menuItems["30 seconds"].awaitExistence(timeout: 2))
        app.typeKey(.escape, modifierFlags: [])
        try require(app.menuItems["30 seconds"].awaitNonExistence())
      },

      // Edit on any row opens every fact Save proves together, with that row's field taking the
      // keys, so the keyboard press and the click land in the same place.
      Law("Return on Edit opens the editor with that field focused") { app in
        app.typeText("kkkk")
        self.assertValue("Bar on", of: app.staticTexts["miniwhisper.profiles.row.endpoint.state"])
        app.typeKey(.return, modifierFlags: [])
        let endpoint = app.textFields["miniwhisper.profiles.endpoint.field"]
        try require(endpoint.awaitExistence(timeout: 2))
        self.assertKeyboardFocus(on: endpoint)
        self.assertValue("https://gateway.example/v1", of: endpoint)
        XCTAssertTrue(app.textFields["miniwhisper.profiles.apiKey.field"].exists)
        XCTAssertTrue(app.popUpButtons["miniwhisper.profiles.model"].exists)
        XCTAssertTrue(app.buttons["miniwhisper.profiles.cancel"].exists)
        XCTAssertTrue(app.buttons["miniwhisper.profiles.save"].exists)
      },

      Law("An address that does not answer is blamed under the address") { app in
        let endpoint = app.textFields["miniwhisper.profiles.endpoint.field"]
        try require(endpoint.awaitExistence(timeout: 2))
        endpoint.doubleClick()
        endpoint.typeKey("a", modifierFlags: .command)
        endpoint.typeText("http://localhost:11435/v1")
        app.buttons["miniwhisper.profiles.save"].click()
        let failure = app.staticTexts["miniwhisper.profiles.failure"]
        self.assertValue("Couldn’t reach localhost:11435.", of: failure)
        XCTAssertGreaterThan(failure.frame.minY, endpoint.frame.maxY)
        XCTAssertLessThan(failure.frame.minY, app.textFields["miniwhisper.profiles.apiKey.field"]
          .frame.minY)
        self.recordScreenshot("profiles-fail-unreachable", screenshot: app.screenshot())
      },

      Law("Cancel throws the draft away, and nothing it held was kept") { app in
        let cancel = app.buttons["miniwhisper.profiles.cancel"]
        try require(cancel.awaitHittable(timeout: 2))
        cancel.click()
        let address = app.staticTexts["miniwhisper.profiles.endpoint.value"]
        try require(address.awaitExistence(timeout: 2))
        self.assertValue("https://gateway.example/v1", of: address)
        XCTAssertTrue(app.staticTexts["miniwhisper.profiles.failure"].awaitNonExistence())
      },

      Law("A refused key is blamed under the key, and the stored one stays") { app in
        let replace = app.buttons["miniwhisper.profiles.apiKey.edit"]
        try require(replace.awaitHittable(timeout: 2))
        replace.click()
        let key = app.textFields["miniwhisper.profiles.apiKey.field"]
        try require(key.awaitExistence(timeout: 2))
        self.assertKeyboardFocus(on: key)
        app.typeText("sk-rejected-0123")
        app.buttons["miniwhisper.profiles.save"].click()
        self.assertValue("Invalid key.", of: app.staticTexts["miniwhisper.profiles.failure"])
        self.assertKeyboardFocus(on: key)
        app.buttons["miniwhisper.profiles.cancel"].click()
        self.assertValue(
          "sk-age••••••••••••", of: app.staticTexts["miniwhisper.profiles.apiKey.value"],
        )
      },

      Law("An unknown model is blamed under the model, and a known one saves") { app in
        let edit = app.buttons["miniwhisper.profiles.model.edit"]
        try require(edit.awaitHittable(timeout: 2))
        edit.click()
        let picker = app.popUpButtons["miniwhisper.profiles.model"]
        try require(picker.awaitExistence(timeout: 2))
        picker.click()
        try require(app.menuItems["Custom…"].awaitExistence(timeout: 2))
        app.menuItems["Custom…"].click()
        let modelID = app.textFields["miniwhisper.profiles.model.custom"]
        try require(modelID.awaitExistence(timeout: 2))
        modelID.click()
        modelID.typeKey("a", modifierFlags: .command)
        modelID.typeText("qwen3:32b")
        app.buttons["miniwhisper.profiles.save"].click()
        self.assertValue(
          "gateway.example has no model ‘qwen3:32b’.",
          of: app.staticTexts["miniwhisper.profiles.failure"],
        )
        self.assertKeyboardFocus(on: modelID)
        self.recordScreenshot("profiles-fail-unknown-model", screenshot: app.screenshot())

        modelID.typeKey("a", modifierFlags: .command)
        modelID.typeText("gpt-oss-20b")
        app.buttons["miniwhisper.profiles.save"].click()
        let model = app.staticTexts["miniwhisper.profiles.model.value"]
        try require(model.awaitExistence(timeout: 2))
        self.assertValue("gpt-oss-20b", of: model)
        XCTAssertFalse(app.buttons["miniwhisper.profiles.save"].exists)
      },

      // Choosing is immediate and total: the rows below are the chosen profile's, its key is its
      // own, and Custom's switch and sidecar leave with Custom.
      Law("Choosing a profile makes it the one the pane describes") { app in
        let picker = app.popUpButtons["miniwhisper.profiles.picker"]
        try require(picker.awaitHittable(timeout: 2))
        picker.click()
        // The item's title leads with its symbol, so it is matched by name rather than equality.
        let haiku = app.menuItems
          .matching(
            NSPredicate(format: "title CONTAINS %@", "Parakeet + Claude Haiku"),
          )
          .firstMatch
        try require(haiku.awaitExistence(timeout: 2))
        haiku.click()
        self.assertValue(
          "https://api.anthropic.com/v1",
          of: app.staticTexts["miniwhisper.profiles.endpoint.value"],
        )
        self.assertValue(
          "sk-ant••••••••••••", of: app.staticTexts["miniwhisper.profiles.apiKey.value"],
        )
        self.assertValue(
          "claude-haiku-5-5", of: app.staticTexts["miniwhisper.profiles.model.value"],
        )
        XCTAssertTrue(app.switches["miniwhisper.profiles.enabled"].awaitNonExistence())
        XCTAssertTrue(app.switches["miniwhisper.profiles.boosts-vocabulary"].awaitNonExistence())
      },
    ])
  }

  @MainActor func testCustomIsSetUpByItsFirstSave() {
    let app = launch("settings-profiles-unconfigured")
    defer { terminate(app) }

    let setUp = app.buttons["miniwhisper.profiles.set-up"]
    XCTAssertTrue(setUp.awaitHittable(timeout: 5))
    // Before its first Save, Custom has no cleanup to switch.
    XCTAssertFalse(app.switches["miniwhisper.profiles.enabled"].exists)
    recordScreenshot("profiles-custom-not-set-up", screenshot: app.screenshot())

    setUp.click()
    let endpoint = app.textFields["miniwhisper.profiles.endpoint.field"]
    XCTAssertTrue(endpoint.awaitExistence(timeout: 2))
    assertKeyboardFocus(on: endpoint)
    app.typeText("http://localhost:11434/v1")
    let modelID = app.textFields["miniwhisper.profiles.model.custom"]
    modelID.click()
    modelID.typeText("gpt-oss:20b")
    recordScreenshot("profiles-custom-editing", screenshot: app.screenshot())
    // No key: an endpoint on this Mac takes none.
    app.buttons["miniwhisper.profiles.save"].click()

    let toggle = app.switches["miniwhisper.profiles.enabled"]
    XCTAssertTrue(toggle.awaitExistence(timeout: 2))
    assertValue("1", of: toggle)
    assertValue(
      "http://localhost:11434/v1", of: app.staticTexts["miniwhisper.profiles.endpoint.value"],
    )
    assertValue("None", of: app.staticTexts["miniwhisper.profiles.apiKey.value"])
    recordScreenshot("profiles-custom-saved", screenshot: app.screenshot())
  }

  @MainActor func testOverriddenFieldResetsToItsFactoryValue() {
    let app = launch("settings-profiles-overridden")
    defer { terminate(app) }

    let address = app.staticTexts["miniwhisper.profiles.endpoint.value"]
    XCTAssertTrue(address.awaitExistence(timeout: 5))
    assertValue("https://aig.thurstons.house/v1", of: address)
    let reset = app.buttons["miniwhisper.profiles.endpoint.reset"]
    XCTAssertTrue(reset.awaitHittable(timeout: 2))
    // After Edit, so Edit never moves when the icon comes and goes.
    XCTAssertGreaterThan(reset.frame.minX, app.buttons["miniwhisper.profiles.endpoint.edit"]
      .frame.maxX)
    XCTAssertFalse(app.buttons["miniwhisper.profiles.model.reset"].exists)
    recordScreenshot("profiles-overridden", screenshot: app.screenshot())

    reset.click()
    assertValue("https://api.anthropic.com/v1", of: address)
    XCTAssertTrue(reset.awaitNonExistence())
  }

  @MainActor func testRefusedKeyReadsInvalidInBothPlaces() {
    let app = launch("settings-profiles-rejected")
    defer { terminate(app) }

    let picker = app.popUpButtons["miniwhisper.profiles.picker"]
    XCTAssertTrue(picker.awaitExistence(timeout: 5))
    assertValue("Parakeet + Claude Haiku; Invalid key", of: picker)
    recordScreenshot("profiles-rejected", screenshot: app.screenshot())
  }
}
