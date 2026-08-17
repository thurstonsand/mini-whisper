import XCTest

/// The default settings scene's keyboard and pointer grammar. Each law leaves the window in a
/// known state; returning through the sidebar and clamping at the first row gives the next law a
/// cheap reset without paying for another process launch.
final class SettingsKeyboardUITests: MiniWhisperUITestCase, SurfaceTagged {
  // MARK: Internal

  static let surfaces: Set<Surface> = [.settings]

  @MainActor func testSettingsLaws() {
    assertLaws(on: "settings", [
      Law("Entering detail paints the first cursor") { app in
        try require(
          app.groups["miniwhisper.settings.shortcut.activate"].awaitExistence(timeout: 5),
        )
        app.typeText("jkl")
        self.assertValue("Not focused", of: app.outlines["miniwhisper.settings.sidebar"])
        self.assertValue(
          "Bar on", of: app.staticTexts["miniwhisper.settings.shortcut.activate.state"],
        )
        self.assertValue(
          "Ring on", of: app.buttons["miniwhisper.settings.shortcut.binding.0"],
        )
      },

      Law("Returning to the sidebar clears cursor paint") { app in
        try require(self.enterDetailAtFirstRow(app))
        app.typeText("h")
        self.assertValue("Focused", of: app.outlines["miniwhisper.settings.sidebar"])
        self.assertValue(
          "Bar off", of: app.staticTexts["miniwhisper.settings.shortcut.activate.state"],
        )
        self.assertValue(
          "Ring off", of: app.buttons["miniwhisper.settings.shortcut.binding.0"],
        )
      },

      // Every letter the grammar names must be consumed wherever the grammar is active. An
      // unclaimed one reaches the sidebar List, which type-selects on it — and "h", the move for
      // "go left", is the first letter of History.
      Law("Grammar keys never reach the sidebar's type-select") { app in
        try require(self.enterDetailAtFirstRow(app))
        app.typeText("h")
        self.assertValue("Focused", of: app.outlines["miniwhisper.settings.sidebar"])
        self.assertValue(
          "Settings; Selected",
          of: app.staticTexts["miniwhisper.settings.sidebar.settings"],
        )
        app.typeText("hhh")
        self.assertValue(
          "Settings; Selected",
          of: app.staticTexts["miniwhisper.settings.sidebar.settings"],
        )
        self.assertValue(
          "History; Not selected",
          of: app.staticTexts["miniwhisper.settings.sidebar.history"],
        )
      },

      Law("The microphone row joins the keyboard grammar") { app in
        try require(self.enterDetailAtFirstRow(app))
        let picker = app.popUpButtons["miniwhisper.settings.microphone.picker"]
        app.typeText("jj")
        self.assertValue(
          "Bar on", of: app.staticTexts["miniwhisper.settings.microphone.state"],
        )
        self.assertValue(
          "Bar off", of: app.staticTexts["miniwhisper.settings.shortcut.activate.state"],
        )

        app.typeKey(.return, modifierFlags: [])
        try require(
          app.menuItems["System Default (MacBook Pro Microphone)"].awaitExistence(timeout: 2),
        )
        app.typeKey(.escape, modifierFlags: [])
        try require(
          app.menuItems["System Default (MacBook Pro Microphone)"].awaitNonExistence(),
        )
        XCTAssertTrue(picker.exists)
      },

      Law("Sound rows join the keyboard grammar") { app in
        try require(self.enterDetailAtFirstRow(app))
        for cue in [
          "shortcut.paste-last",
          "microphone",
          "sound.activate",
          "sound.complete",
          "sound.cancel",
          "sound.error",
        ] {
          app.typeText("j")
          self.assertValue("Bar on", of: app.staticTexts["miniwhisper.settings.\(cue).state"])
        }
        app.typeText("kkkkkk")
        self.assertValue(
          "Bar on", of: app.staticTexts["miniwhisper.settings.shortcut.activate.state"],
        )
      },

      Law("Return opens a sound popup") { app in
        try require(self.enterDetailAtFirstRow(app))
        app.typeText("jjj")
        self.assertValue(
          "Bar on", of: app.staticTexts["miniwhisper.settings.sound.activate.state"],
        )
        app.typeKey(.return, modifierFlags: [])
        try require(app.menuItems["No audio"].awaitExistence(timeout: 2))
        XCTAssertTrue(app.menuItems["Tink (default)"].exists)
        app.typeKey(.escape, modifierFlags: [])
        try require(app.menuItems["No audio"].awaitNonExistence())

        app.typeText("h")
        self.assertValue("Focused", of: app.outlines["miniwhisper.settings.sidebar"])
      },

      Law("Launch at login completes the pane") { app in
        try require(self.enterDetailAtFirstRow(app))
        let toggle = app.switches["miniwhisper.settings.launch-at-login"]
        XCTAssertEqual(self.accessibilityValue(toggle), "1")

        app.typeText(String(repeating: "j", count: 8))
        self.assertValue(
          "Bar on", of: app.staticTexts["miniwhisper.settings.launch-at-login.state"],
        )
        self.assertValue(
          "Ring on", of: app.staticTexts["miniwhisper.settings.launch-at-login.ring"],
        )
        XCTAssertTrue(toggle.isHittable)

        app.typeKey(.return, modifierFlags: [])
        self.assertValue("0", of: toggle)
      },

      Law("A sound preview fires the injected client") { app in
        let preview = app.buttons["miniwhisper.settings.sound.activate.preview"]
        try require(preview.awaitExistence(timeout: 2))
        preview.click()
        self.assertValue("Tink", of: app.staticTexts["miniwhisper.settings.sound.playback"])
      },

      Law("The microphone row answers the pointer") { app in
        let picker = app.popUpButtons["miniwhisper.settings.microphone.picker"]
        let row = app.descendants(matching: .any)["miniwhisper.settings.microphone"]
        try require(picker.awaitExistence(timeout: 2))
        self.hoverAfterEnteringWindow(row, in: app)
        self.assertValue("Bar on", of: app.staticTexts["miniwhisper.settings.microphone.state"])

        picker.click()
        let studio = app.menuItems["Studio Microphone"]
        try require(studio.awaitExistence(timeout: 2))
        studio.click()
        self.assertValue("Studio Microphone", of: picker)
      },

      Law("Hover survives keyboard-mode entry") { app in
        try require(self.enterDetailAtFirstRow(app))
        let row = app.groups["miniwhisper.settings.shortcut.activate"]
        let rowState = app.staticTexts["miniwhisper.settings.shortcut.activate.state"]
        let binding = app.buttons["miniwhisper.settings.shortcut.binding.0"]
        self.hoverAfterEnteringWindow(row, in: app)
        self.assertValue("Bar on", of: rowState)
        self.assertValue("Ring off", of: binding)

        app.typeText("k")
        self.assertValue("Bar on", of: rowState)
        self.assertValue("Ring on", of: binding)
      },

      Law("Keyboard movement continues from the hovered row") { app in
        try require(self.enterDetailAtFirstRow(app))
        let errorRow = app.groups["miniwhisper.settings.sound.error"]
        self.hoverAfterEnteringWindow(errorRow, in: app)
        self.assertValue(
          "Bar on", of: app.staticTexts["miniwhisper.settings.sound.error.state"],
        )

        app.typeText("k")
        self.assertValue(
          "Bar on", of: app.staticTexts["miniwhisper.settings.sound.cancel.state"],
        )
        self.assertValue(
          "Ring off", of: app.buttons["miniwhisper.settings.sound.cancel.preview"],
        )
      },
    ])
  }

  // MARK: Private

  @MainActor private func enterDetailAtFirstRow(_ app: XCUIApplication) -> Bool {
    // One synthesis call: every typeText costs a few hundred milliseconds of event synthesis
    // and idle-waiting regardless of how many characters it carries.
    app.typeText("hl" + String(repeating: "k", count: 8))
    let landed = poll {
      app.staticTexts["miniwhisper.settings.shortcut.activate.state"].exists
    }
    guard landed else {
      XCTFail(
        """
        The shortcut row left the accessibility tree entirely after entering the detail column.
        \(app.debugDescription)
        """,
      )
      return false
    }
    return poll {
      self.accessibilityValue(
        app.staticTexts["miniwhisper.settings.shortcut.activate.state"],
      ) == "Bar on"
    }
  }
}
