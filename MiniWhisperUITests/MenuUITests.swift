import AppKit
import XCTest

// MARK: - MenuUITests

final class MenuUITests: MiniWhisperUITestCase, SurfaceTagged {
  // MARK: Internal

  static let surfaces: Set<Surface> = [.menu]

  @MainActor func testMenuAccessibilityManifest() throws {
    try assertMenuManifest(
      scene: "menu-healthy",
      elements: [
        contract(
          .menuItem, "miniwhisper.menu.status", "Status", "Ready; Parakeet v2; Test Microphone",
          isEnabled: false,
        ),
        contract(
          .menuItem, "miniwhisper.menu.copy-last-transcript", "Copy Last Transcript",
          isEnabled: true, isActionable: true,
        ),
        contract(.menuItem, "miniwhisper.menu.quick-add", "Add to Dictionary…"),
        contract(
          .button, "miniwhisper.menu.quick-add.header", "Add to Dictionary…",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .menuItem, "miniwhisper.menu.settings", "Settings", isEnabled: true,
          isActionable: true,
        ),
        contract(
          .menuItem, "miniwhisper.menu.about", "About \(appName)", isEnabled: true,
          isActionable: true,
        ),
        contract(
          .menuItem, "miniwhisper.menu.quit", "Quit \(appName)", isEnabled: true,
          isActionable: true,
        ),
      ],
    )

    try assertMenuManifest(
      scene: "menu-degraded",
      elements: [
        contract(
          .menuItem, "miniwhisper.menu.status", "Status",
          "Not ready; Test Microphone", isEnabled: false,
        ),
        contract(
          .menuItem, "miniwhisper.menu.repair.accessibility", "Grant Accessibility Access…",
          "Required to start dictation and paste text",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .menuItem, "miniwhisper.menu.repair.microphone", "Grant Microphone Access…",
          "Required to record audio",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .menuItem, "miniwhisper.menu.copy-last-transcript", "Copy Last Transcript",
          isEnabled: false,
        ),
        contract(.menuItem, "miniwhisper.menu.quick-add", "Add to Dictionary…"),
        contract(
          .button, "miniwhisper.menu.quick-add.header", "Add to Dictionary…",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .menuItem, "miniwhisper.menu.settings", "Settings", isEnabled: true,
          isActionable: true,
        ),
        contract(
          .menuItem, "miniwhisper.menu.about", "About \(appName)", isEnabled: true,
          isActionable: true,
        ),
        contract(
          .menuItem, "miniwhisper.menu.quit", "Quit \(appName)", isEnabled: true,
          isActionable: true,
        ),
      ],
    )

    try assertMenuManifest(
      scene: "menu-healthy",
      elements: [
        contract(
          .menuItem, "miniwhisper.menu.status", "Status", "Ready; Parakeet v2; Test Microphone",
          isEnabled: false,
        ),
        contract(
          .menuItem, "miniwhisper.menu.copy-last-transcript", "Copy Last Transcript",
          isEnabled: true, isActionable: true,
        ),
        contract(.menuItem, "miniwhisper.menu.quick-add", "Add to Dictionary…"),
        contract(
          .button, "miniwhisper.menu.quick-add.header", "Add to Dictionary…", isEnabled: false,
        ),
        contract(
          .textField, "miniwhisper.menu.quick-add.word", "Correct spelling", isEnabled: true,
        ),
        contract(
          .button, "miniwhisper.menu.quick-add.disclosure", "Misheard as…", isEnabled: false,
        ),
        contract(
          .textField, "miniwhisper.menu.quick-add.misspelling", "Misspelling", isEnabled: true,
        ),
        contract(
          .button, "miniwhisper.menu.quick-add.submit", "Add to Dictionary", isEnabled: true,
          isActionable: true,
        ),
        contract(
          .menuItem, "miniwhisper.menu.settings", "Settings", isEnabled: true,
          isActionable: true,
        ),
        contract(
          .menuItem, "miniwhisper.menu.about", "About \(appName)", isEnabled: true,
          isActionable: true,
        ),
        contract(
          .menuItem, "miniwhisper.menu.quit", "Quit \(appName)", isEnabled: true,
          isActionable: true,
        ),
      ],
      mutation: { app in
        let header = app.buttons["miniwhisper.menu.quick-add.header"]
        XCTAssertTrue(header.awaitHittable(timeout: 2))
        header.click()
        let disclosure = app.buttons["miniwhisper.menu.quick-add.disclosure"]
        XCTAssertTrue(disclosure.awaitHittable(timeout: 2))
        disclosure.click()
      },
    )
  }

  @MainActor func testAboutAccessibilityManifest() throws {
    try assertManifest(
      scene: "about",
      audits: true,
      elements: [
        contract(.window, "miniwhisper.about.window", "About \(appName)"),
        contract(.group, "miniwhisper.about.content", "About \(appName)"),
        contract(.image, "miniwhisper.about.icon", "\(appName) icon"),
        contract(.staticText, "miniwhisper.about.app-name", "Application", appName),
        contract(
          .staticText, "miniwhisper.about.version", "Version",
          valuePattern: #"^Version [0-9]+\.[0-9]+(?:\.[0-9]+)? \([0-9]+\)$"#,
        ),
        contract(
          .staticText, "miniwhisper.about.attribution", "Speech recognition attribution",
          "NVIDIA Parakeet TDT 0.6B v2, licensed under CC BY 4.0",
        ),
        contract(
          .link, "miniwhisper.about.model-link", "Open the Parakeet TDT 0.6B v2 model page",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .staticText, "miniwhisper.about.fluid-audio-attribution", "FluidAudio attribution",
          "FluidAudio, licensed under the Apache License 2.0",
        ),
        contract(
          .link, "miniwhisper.about.fluid-audio-link", "Open the FluidAudio project page",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .button, "miniwhisper.about.close", "Close About \(appName)", isEnabled: true,
          isActionable: true,
        ),
      ],
    )
  }

  // MARK: Private

  @MainActor private func assertMenuManifest(
    scene: String, elements: [AccessibilityContract],
    mutation: ((XCUIApplication) -> Void)? = nil,
    file: StaticString = #filePath, line: UInt = #line,
  ) throws {
    let app = launch(scene)
    defer { terminate(app) }
    let statusItem = app.statusItems["miniwhisper.menu.status-item"]
    XCTAssertTrue(statusItem.awaitExistence(timeout: 5), file: file, line: line)
    XCTAssertEqual(statusItem.label, appName, file: file, line: line)
    XCTAssertTrue(statusItem.isEnabled, file: file, line: line)
    // Existing and being clickable are different moments. A status item is placed into the menu
    // bar after it appears in the accessibility tree, and a menu-bar manager (Bartender, Ice) may
    // reshuffle it once more after that — macOS offers the app no way to observe either, so the
    // only honest spelling is to wait for hittable rather than to sample it once.
    XCTAssertTrue(
      statusItem.awaitHittable(timeout: 5),
      """
      Status item never became clickable. If this persists, the menu bar is genuinely out of \
      room: a menu-bar manager is hiding \(appName), or the notch is swallowing it. Reveal the \
      item before running the suite.
      """,
      file: file, line: line,
    )
    statusItem.click()
    XCTAssertTrue(
      app.menuItems[elements[0].identifier].awaitExistence(timeout: 2), file: file, line: line,
    )
    mutation?(app)
    assert(elements, in: app, file: file, line: line)
  }

  // The audit is a property of a presented scene, not a scene of its own, so it rides along with
}
