import XCTest

/// The Models pane's laws: every profile is wired to what it runs on, pointing at a profile
/// lights its wires without making it active, and each model's one button is the way to get its
/// space back or get it at all.
final class ModelsUITests: MiniWhisperUITestCase, SurfaceTagged {
  static let surfaces: Set<Surface> = [.settings]

  @MainActor func testModelsPaneLaws() {
    assertLaws(on: "settings-models", [
      Law("The active profile is lit, and every model says what it weighs") { app in
        let haiku = app.descendants(matching: .any)["miniwhisper.models.card.haiku"]
        try require(haiku.awaitExistence(timeout: 5))
        self.assertValue("Active", of: haiku)
        self.assertValue("", of: app.descendants(matching: .any)["miniwhisper.models.card.offline"])
        self.assertValue(
          "567.2 MB", of: app.staticTexts["miniwhisper.models.asset.parakeet.state"],
        )
        // Only losing what the active profile runs on promises a question.
        self.assertLabel("Delete…", of: app.buttons["miniwhisper.models.asset.parakeet.delete"])
        self.assertLabel("Delete", of: app.buttons["miniwhisper.models.asset.s1-mini.delete"])
        self.recordScreenshot("models", screenshot: app.screenshot())
      },

      Law("Pointing at a profile lights it, and it stays lit without becoming active") { app in
        let offline = app.descendants(matching: .any)["miniwhisper.models.card.offline"]
        try require(offline.awaitHittable(timeout: 2))
        self.hoverAfterEnteringWindow(offline, in: app)
        self.assertValue("Preview", of: offline)
        self.assertValue(
          "Active", of: app.descendants(matching: .any)["miniwhisper.models.card.haiku"],
        )
        app.buttons["miniwhisper.models.asset.s1-mini.delete"].hover()
        self.assertValue("Preview", of: offline)
        self.recordScreenshot("models-hover-offline", screenshot: app.screenshot())
      },

      Law("Leaving clears pointer preview; keyboard preview survives asset rows until Escape") { app in
        let offline = app.descendants(matching: .any)["miniwhisper.models.card.offline"]
        app.staticTexts["miniwhisper.settings.sidebar.history"].hover()
        self.assertValue("", of: offline)
        offline.hover()
        self.assertValue("Preview", of: offline)
        app.typeText("jjjj")
        let custom = app.descendants(matching: .any)["miniwhisper.models.card.custom"]
        self.assertValue("Preview", of: custom)
        app.typeKey(.escape, modifierFlags: [])
        self.assertValue("", of: custom)
        self.assertValue(
          "Active",
          of: app.descendants(matching: .any)["miniwhisper.models.card.haiku"],
        )
      },

      Law("Deleting what the active profile runs on asks first") { app in
        let delete = app.buttons["miniwhisper.models.asset.parakeet.delete"]
        try require(delete.awaitHittable(timeout: 2))
        delete.click()
        let cancel = app.sheets.buttons["Cancel"].firstMatch
        try require(cancel.awaitExistence(timeout: 2))
        XCTAssertTrue(app.sheets
          .staticTexts[
            "Everyday can’t transcribe until it’s downloaded again.",
          ]
          .awaitExistence())
        cancel.click()
        XCTAssertTrue(cancel.awaitNonExistence())
        self.assertValue(
          "567.2 MB", of: app.staticTexts["miniwhisper.models.asset.parakeet.state"],
        )
      },

      Law("Deleting Offline cleanup warns of raw delivery, not lost transcription") { app in
        app.staticTexts["miniwhisper.settings.sidebar.profiles"].click()
        let picker = app.popUpButtons["miniwhisper.profiles.picker"]
        try require(picker.awaitHittable(timeout: 2))
        picker.click()
        let offline = app.menuItems
          .matching(NSPredicate(format: "title CONTAINS %@", "Offline"))
          .firstMatch
        try require(offline.awaitExistence(timeout: 2))
        offline.click()
        app.staticTexts["miniwhisper.settings.sidebar.models"].click()
        let delete = app.buttons["miniwhisper.models.asset.s1-mini.delete"]
        try require(delete.awaitHittable(timeout: 2))
        delete.click()
        let cancel = app.sheets.buttons["Cancel"].firstMatch
        try require(cancel.awaitExistence(timeout: 2))
        self.recordScreenshot("offline-delete-confirmation", screenshot: app.screenshot())
        XCTAssertTrue(app.sheets
          .staticTexts[
            "MiniWhisper will deliver transcripts without cleanup.",
          ]
          .awaitExistence())
        cancel.click()
        XCTAssertTrue(cancel.awaitNonExistence())
      },
    ])
  }

  @MainActor func testModelsPaneSaysWhatIsDownloadingAndWhatFailed() {
    let app = launch("settings-models-states")
    defer { terminate(app) }

    let parakeet = app.staticTexts["miniwhisper.models.asset.parakeet.state"]
    XCTAssertTrue(parakeet.awaitExistence(timeout: 5))
    assertValue("42%", of: parakeet)
    assertValue("Failed", of: app.staticTexts["miniwhisper.models.asset.s1-mini.state"])
    assertLabel("Retry", of: app.buttons["miniwhisper.models.asset.s1-mini.download"])
    recordScreenshot("models-states", screenshot: app.screenshot())
  }

  @MainActor func testMissingKeyOpensItsProfileFieldAndRepairClearsTheProblem() {
    assertLaws(on: "settings-models-key-missing", [
      Law("Only the speech leg is broken") { app in
        let key = app.buttons["miniwhisper.models.component.scribe.key"]
        try require(key.awaitHittable())
        XCTAssertFalse(app.buttons["miniwhisper.models.component.endpoint.accurate.key"].exists)
        self.recordScreenshot("models-key-missing", screenshot: app.screenshot())
        key.click()
        self.assertKeyboardFocus(on: app.textFields["miniwhisper.profiles.engineKey.field"])
      },
      Law("Saving the key repairs the chain on return") { app in
        app.textFields["miniwhisper.profiles.engineKey.field"].typeText("sk-speech-scene")
        app.buttons["miniwhisper.profiles.save"].click()
        self.assertValue(
          "sk-spe••••••••••••",
          of: app.staticTexts["miniwhisper.profiles.engineKey.value"],
        )
        app.staticTexts["miniwhisper.settings.sidebar.models"].click()
        try require(app.descendants(matching: .any)["miniwhisper.models.card.accurate"]
          .awaitExistence())
        XCTAssertTrue(app.buttons["miniwhisper.models.component.scribe.key"].awaitNonExistence())
        self.recordScreenshot("models-key-repaired", screenshot: app.screenshot())
        app.buttons["miniwhisper.models.component.endpoint.haiku.key"].click()
        self.assertKeyboardFocus(on: app.textFields["miniwhisper.profiles.apiKey.field"])
      },
    ])
  }
}
