import AppKit
import XCTest

// MARK: - PillUITests

final class PillUITests: MiniWhisperUITestCase, SurfaceTagged {
  static let surfaces: Set<Surface> = [.pill]

  @MainActor func testPillAccessibilityManifest() throws {
    let app = launch("pill-recording")
    defer { terminate(app) }
    try assertManifest(
      in: app,
      elements: [
        contract(.dialog, "miniwhisper.pill", "\(appName) dictation", "Visible"),
        contract(.staticText, "miniwhisper.pill.phase", "Dictation phase", "Recording"),
        contract(.staticText, "miniwhisper.pill.capture-status", "Capture status", "Live"),
        contract(.staticText, "miniwhisper.pill.input-device", "Input device", "Test Microphone"),
        contract(.staticText, "miniwhisper.pill.audio-level", "Input level", "70%"),
      ],
      mutation: { app in
        let level = app.descendants(matching: .any)["miniwhisper.pill.audio-level"]
        self.postAgentMutation("pill-level", value: 0.23)
        self.assertValue("20%", of: level)
      },
    )
    XCTAssertLessThanOrEqual(app.staticTexts["miniwhisper.pill.input-device"].frame.width, 1)
    presentScene("pill-recording-selected-input")
    assertValue("Studio Microphone", of: app.staticTexts["miniwhisper.pill.input-device"])
    XCTAssertGreaterThan(app.staticTexts["miniwhisper.pill.input-device"].frame.width, 50)
    presentScene("pill-transcribing")
    try assertManifest(
      in: app,
      elements: [
        contract(.dialog, "miniwhisper.pill", "\(appName) dictation", "Visible"),
        contract(.staticText, "miniwhisper.pill.phase", "Dictation phase", "Transcribing"),
      ],
    )
    presentScene("pill-no-speech")
    try assertManifest(
      in: app,
      elements: [
        contract(.dialog, "miniwhisper.pill", "\(appName) dictation", "Visible"),
        contract(.staticText, "miniwhisper.pill.phase", "Dictation phase", "No speech detected"),
        contract(.staticText, "miniwhisper.pill.notice", "Dictation notice", "No speech detected"),
      ],
    )
    presentScene("pill-copied")
    try assertManifest(
      in: app,
      elements: [
        contract(.dialog, "miniwhisper.pill", "\(appName) dictation", "Visible"),
        contract(.staticText, "miniwhisper.pill.phase", "Dictation phase", "Copied"),
        contract(
          .staticText, "miniwhisper.pill.notice", "Dictation notice", "Copied — ⌘V to paste",
        ),
      ],
    )
    presentScene("pill-nowhere-to-paste")
    assertValue("Copied — ⌘V to paste", of: app.staticTexts["miniwhisper.pill.notice"])
    presentScene("pill-model-unavailable")
    assertValue(
      "Dictation not started\nDownloading Parakeet v2 · 42%",
      of: app.staticTexts["miniwhisper.pill.notice"],
    )
    presentScene("pill-polishing-skip")
    let destination = app.staticTexts["miniwhisper.pill.destination"]
    let skip = app.staticTexts["miniwhisper.pill.skip-affordance"]
    let phase = app.staticTexts["miniwhisper.pill.phase"]
    XCTAssertTrue(destination.awaitExistence())
    XCTAssertTrue(skip.awaitExistence())
    XCTAssertTrue(poll { skip.frame.maxY < destination.frame.minY })
    XCTAssertTrue(poll { abs(skip.frame.midY - phase.frame.midY) < 2 })
    assertValue("Cleaning up", of: phase)
    let submits = app.staticTexts["miniwhisper.pill.submits"]
    XCTAssertTrue(submits.awaitExistence())
    XCTAssertTrue(poll { abs(submits.frame.midY - destination.frame.midY) < 2 })
    presentScene("pill-polishing-long-shortcut")
    XCTAssertTrue(skip.awaitExistence())
    let panel = app.dialogs["miniwhisper.pill"]
    XCTAssertTrue(poll {
      skip.frame.maxX <= panel.frame.maxX && phase.frame.minX >= panel.frame.minX
    })
    XCTAssertTrue(poll { skip.frame.maxY < destination.frame.minY })
  }
}
