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
        self.assertValue("Active; Highlighted", of: haiku)
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
        self.assertValue("Highlighted", of: offline)
        self.assertValue(
          "Active", of: app.descendants(matching: .any)["miniwhisper.models.card.haiku"],
        )
        app.buttons["miniwhisper.models.asset.s1-mini.delete"].hover()
        self.assertValue("Highlighted", of: offline)
        self.recordScreenshot("models-hover-offline", screenshot: app.screenshot())
      },

      Law("Deleting what the active profile runs on asks first") { app in
        let delete = app.buttons["miniwhisper.models.asset.parakeet.delete"]
        try require(delete.awaitHittable(timeout: 2))
        delete.click()
        let cancel = app.sheets.buttons["Cancel"].firstMatch
        try require(cancel.awaitExistence(timeout: 2))
        cancel.click()
        XCTAssertTrue(cancel.awaitNonExistence())
        self.assertValue(
          "567.2 MB", of: app.staticTexts["miniwhisper.models.asset.parakeet.state"],
        )
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
}
