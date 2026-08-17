import AppKit
import XCTest

// MARK: - SettingsUITests

final class SettingsUITests: MiniWhisperUITestCase, SurfaceTagged {
  // MARK: Internal

  static let surfaces: Set<Surface> = [.settings]

  @MainActor func testSettingsAccessibilityManifest() throws {
    try assertManifest(
      scene: "settings",
      elements: [
        contract(.window, "miniwhisper.settings.window", "\(appName) Settings"),
        contract(.outline, "miniwhisper.settings.sidebar", "Settings sections", "Focused"),
        contract(
          .staticText, "miniwhisper.settings.sidebar.settings", "Settings section",
          "Settings; Selected",
        ),
        contract(
          .staticText, "miniwhisper.settings.sidebar.history", "History section",
          "History; Not selected",
        ),
        contract(
          .staticText, "miniwhisper.settings.sidebar.model", "Model section",
          "Model; Not selected",
        ),
        contract(
          .staticText, "miniwhisper.settings.sidebar.dictionary", "Dictionary section",
          "Dictionary; Not selected",
        ),
        contract(
          .staticText, "miniwhisper.settings.sidebar.cleanup", "Cleanup section",
          "Cleanup; Not selected",
        ),
        contract(.group, "miniwhisper.settings.shortcut.activate", "Activate shortcut"),
        contract(
          .staticText, "miniwhisper.settings.shortcut.activate.state",
          "Activate shortcut highlight", "Bar off",
        ),
        contract(
          .button, "miniwhisper.settings.shortcut.binding.0", "⌥ Opt →", "Ring off",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .button, "miniwhisper.settings.shortcut.binding.1", "⌃ Ctrl → R", "Ring off",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .menuButton, "miniwhisper.settings.shortcut.menu", "Shortcut actions", isEnabled: true,
          isActionable: true,
        ),
        contract(
          .group, "miniwhisper.settings.shortcut.paste-last", "Paste last transcript shortcut",
        ),
        contract(
          .staticText, "miniwhisper.settings.shortcut.paste-last.state",
          "Paste last transcript shortcut highlight", "Bar off",
        ),
        contract(
          .button, "miniwhisper.settings.shortcut.paste-last.binding.0",
          "⌥ Opt ← ⌘ Cmd ← V", "Ring off", isEnabled: true, isActionable: true,
        ),
        contract(
          .menuButton, "miniwhisper.settings.shortcut.paste-last.menu", "Shortcut actions",
          isEnabled: true, isActionable: true,
        ),
        contract(.group, "miniwhisper.settings.microphone", "Microphone"),
        contract(
          .staticText, "miniwhisper.settings.microphone.state", "Microphone highlight",
          "Bar off",
        ),
        contract(
          .staticText, "miniwhisper.settings.microphone.level", "Microphone input level", "0.42",
        ),
        contract(
          .popUpButton, "miniwhisper.settings.microphone.picker", "Microphone input",
          "System Default (MacBook Pro Microphone)", isEnabled: true, isActionable: true,
        ),
        contract(.group, "miniwhisper.settings.sound.activate", "Activate"),
        contract(
          .staticText, "miniwhisper.settings.sound.activate.state", "Activate highlight",
          "Bar off",
        ),
        contract(
          .button, "miniwhisper.settings.sound.activate.preview",
          "Preview activate sound", "Ring off", isEnabled: true, isActionable: true,
        ),
        contract(
          .popUpButton, "miniwhisper.settings.sound.activate.picker", "Activate sound",
          "Tink (default)", isEnabled: true, isActionable: true,
        ),
        contract(
          .staticText, "miniwhisper.settings.sound.activate.picker.state",
          "Activate sound emphasis", "Primary",
        ),
        contract(.group, "miniwhisper.settings.sound.complete", "Complete"),
        contract(
          .staticText, "miniwhisper.settings.sound.complete.state", "Complete highlight", "Bar off",
        ),
        contract(
          .button, "miniwhisper.settings.sound.complete.preview", "Preview complete sound",
          "Ring off",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .popUpButton, "miniwhisper.settings.sound.complete.picker", "Complete sound",
          "Pop (default)",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .staticText, "miniwhisper.settings.sound.complete.picker.state",
          "Complete sound emphasis",
          "Primary",
        ),
        contract(.group, "miniwhisper.settings.sound.cancel", "Cancel"),
        contract(
          .staticText, "miniwhisper.settings.sound.cancel.state", "Cancel highlight", "Bar off",
        ),
        contract(
          .button, "miniwhisper.settings.sound.cancel.preview", "Preview cancel sound", "Ring off",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .popUpButton, "miniwhisper.settings.sound.cancel.picker", "Cancel sound",
          "Funk (default)",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .staticText, "miniwhisper.settings.sound.cancel.picker.state", "Cancel sound emphasis",
          "Primary",
        ),
        contract(.group, "miniwhisper.settings.sound.error", "Error"),
        contract(
          .staticText, "miniwhisper.settings.sound.error.state", "Error highlight", "Bar off",
        ),
        contract(
          .button, "miniwhisper.settings.sound.error.preview", "Preview error sound", "Ring off",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .popUpButton, "miniwhisper.settings.sound.error.picker", "Error sound",
          "Basso (default)",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .staticText, "miniwhisper.settings.sound.error.picker.state", "Error sound emphasis",
          "Primary",
        ),
        contract(
          .staticText, "miniwhisper.settings.sound.playback", "Sound playback", "None",
        ),
        contract(
          .switch, "miniwhisper.settings.launch-at-login", "Open at login", "1",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .staticText, "miniwhisper.settings.launch-at-login.state",
          "Open at login highlight", "Bar off",
        ),
        contract(
          .staticText, "miniwhisper.settings.launch-at-login.ring",
          "Open at login ring", "Ring off",
        ),
      ],
    )
  }

  @MainActor func testSettingsRepairRowsAreDegradedOnlyAndAreTheirOwnDoor() {
    // The healthy manifest rejects these rows as unexpected; this scene proves their degraded form.
    let app = launch("settings-degraded")
    defer { terminate(app) }
    let accessibility = app.groups["miniwhisper.settings.repair.accessibility"]
    let microphone = app.groups["miniwhisper.settings.repair.microphone"]
    let model = app.groups["miniwhisper.settings.repair.model-setup-failed"]
    XCTAssertTrue(accessibility.awaitExistence(timeout: 5))
    XCTAssertTrue(microphone.exists)
    XCTAssertTrue(model.exists)
    XCTAssertEqual(accessibility.label, "Required to start dictation and paste text")
    XCTAssertEqual(
      app.buttons["miniwhisper.settings.repair.accessibility.action"].label,
      "Grant Accessibility Access…",
    )
    XCTAssertEqual(
      app.buttons["miniwhisper.settings.repair.model-setup-failed.action"].label,
      "Retry Parakeet v2 Setup",
    )
    assertValue(
      "Speech model setup failed", of: app.staticTexts["miniwhisper.settings.engine-status"],
    )

    app.typeText("l")
    app.typeKey(.return, modifierFlags: [])
    waitForAgentResult(
      "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
    )
  }

  @MainActor func testSettingsNoAudioIsSecondaryAndCannotBePreviewed() {
    let app = launch("settings-sounds-no-audio")
    defer { terminate(app) }

    let picker = app.popUpButtons["miniwhisper.settings.sound.cancel.picker"]
    let preview = app.buttons["miniwhisper.settings.sound.cancel.preview"]
    XCTAssertTrue(picker.awaitExistence(timeout: 5))
    assertValue("No audio", of: picker)
    assertValue(
      "Secondary", of: app.staticTexts["miniwhisper.settings.sound.cancel.picker.state"],
    )
    XCTAssertFalse(preview.isEnabled)
  }

  @MainActor func testSettingsUnavailableMicrophoneShowsTruthfulFallback() {
    let app = launch("settings-microphone-unavailable")
    defer { terminate(app) }

    let picker = app.popUpButtons["miniwhisper.settings.microphone.picker"]
    let notice = app.descendants(matching: .any)["miniwhisper.settings.microphone.unavailable"]
    XCTAssertTrue(picker.awaitExistence(timeout: 5))
    XCTAssertTrue(picker.isEnabled)
    XCTAssertEqual(accessibilityValue(picker), "Studio Microphone (Unavailable)")
    // The default device name resolves after the pane appears, so the notice is polled: a fast
    // existence wait no longer grants the free second the old timer-based wait did.
    assertLabel(
      "Studio Microphone not connected. Using system default: MacBook Pro Microphone.",
      of: notice,
    )
  }

  @MainActor func testRealSettingsWindowLaws() {
    // The directly presented agent scene preserves focus and cannot exercise these paths.
    let app = launchRealSettings()
    defer { terminate(app) }

    let sidebar = app.outlines["miniwhisper.settings.sidebar"]
    let settings = app.staticTexts["miniwhisper.settings.sidebar.settings"]
    let history = app.staticTexts["miniwhisper.settings.sidebar.history"]
    assertValue("Focused", of: sidebar)
    assertValue("Settings; Selected", of: settings)

    app.typeText("j")
    assertValue("History; Selected", of: history)
    app.typeText("k")
    assertValue("Settings; Selected", of: settings)

    let bar = app.staticTexts["miniwhisper.settings.launch-at-login.state"]
    // One press per key: a repeated typeText is delivered whole, where a loop drops some.
    app.typeText("ljjjjjjjj")
    assertValue("Bar on", of: bar)

    app.typeText("hjkl")
    assertValue("Bar on", of: bar)
  }

  // MARK: Private

  @MainActor private func launchRealSettings() -> XCUIApplication {
    let app = XCUIApplication()
    app.launch()
    let statusItem = app.statusItems["miniwhisper.menu.status-item"]
    XCTAssertTrue(statusItem.awaitExistence(timeout: 5))
    statusItem.click()
    let settings = app.menuItems["miniwhisper.menu.settings"]
    XCTAssertTrue(settings.awaitExistence(timeout: 2))
    settings.click()
    XCTAssertTrue(app.windows["miniwhisper.settings.window"].awaitExistence(timeout: 5))
    return app
  }
}
