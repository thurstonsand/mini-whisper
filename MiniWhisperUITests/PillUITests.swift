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
  }
}
