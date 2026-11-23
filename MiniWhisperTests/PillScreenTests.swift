import CoreGraphics
@testable import MiniWhisper
import Testing

struct PillScreenTests {
  // MARK: Internal

  /// A window on the display stacked above the primary: Accessibility measures it with negative
  /// y, AppKit with y past the primary's top. Comparing the two unflipped lands it on the primary.
  @Test func `the window's display wins over the pointer's`() {
    let window = CGRect(x: 300, y: -900, width: 800, height: 600)

    #expect(PillScreen.choose(windowFrame: window, mouse: CGPoint(x: 10, y: 10), screens: screens)
      == 1)
  }

  @Test func `a window across two displays belongs to the one holding most of it`() {
    let window = CGRect(x: 1200, y: 100, width: 800, height: 600)

    #expect(PillScreen.choose(windowFrame: window, mouse: CGPoint(x: 10, y: 10), screens: screens)
      == 2)
  }

  @Test func `without a window the pointer's display is used`() {
    #expect(PillScreen.choose(windowFrame: nil, mouse: CGPoint(x: 2000, y: 300), screens: screens)
      == 2)
  }

  @Test func `a window on no display falls back to the pointer`() {
    let offscreen = CGRect(x: -5000, y: -5000, width: 10, height: 10)

    #expect(
      PillScreen.choose(windowFrame: offscreen, mouse: CGPoint(x: 600, y: 1500), screens: screens)
        == 1,
    )
  }

  // MARK: Private

  /// Primary 1440×900 at the origin; a 1920×1080 display stacked above it; a 1920×1080 display
  /// to its right, bottom-aligned.
  private let screens = [
    CGRect(x: 0, y: 0, width: 1440, height: 900),
    CGRect(x: 0, y: 900, width: 1920, height: 1080),
    CGRect(x: 1440, y: 0, width: 1920, height: 1080),
  ]
}
