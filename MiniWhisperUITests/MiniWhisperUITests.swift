//
//  MiniWhisperUITests.swift
//  MiniWhisperUITests
//
//  Created by Thurston Sandberg on 12/19/25.
//

import XCTest

final class MiniWhisperUITests: XCTestCase {

  override func setUpWithError() throws {
    // Put setup code here. This method is called before the invocation of each test method in the class.

    // In UI tests it is usually best to stop immediately when a failure occurs.
    continueAfterFailure = false

    // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
  }

  override func tearDownWithError() throws {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
  }

  @MainActor func testMenuContainsQuitItem() throws {
    let app = XCUIApplication()
    app.launch()

    let statusItem = app.statusItems["MiniWhisperStatusItem"]
    XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
    try XCTSkipIf(!statusItem.isHittable, "Status item is hidden by menu bar overflow.")
    statusItem.click()

    let quitItem = app.menuItems["Quit"]
    XCTAssertTrue(quitItem.waitForExistence(timeout: 2))
  }

  @MainActor func testLaunchPerformance() throws {
    throw XCTSkip("Launch performance metrics are unstable for the menu bar test host.")
  }
}
