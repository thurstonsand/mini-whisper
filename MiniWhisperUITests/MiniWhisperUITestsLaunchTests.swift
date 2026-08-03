import XCTest

final class MiniWhisperUITestsLaunchTests: XCTestCase {
  override class var runsForEachTargetApplicationUIConfiguration: Bool {
    true
  }

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor func testLaunch() {
    let app = XCUIApplication()
    app.launchEnvironment["MINIWHISPER_AGENT_SCENE"] = "onboarding-welcome"
    app.launchEnvironment["MINIWHISPER_AGENT_COMMAND_FILE"] =
      FileManager.default
        .temporaryDirectory
        .appending(
          path: "miniwhisper-agent-driveability-launch",
        )
        .path
    app.launch()

    XCTAssertTrue(app.windows["miniwhisper.onboarding.window"].waitForExistence(timeout: 5))
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = "Accessible onboarding launch"
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
