@testable import MiniWhisper
import Testing

struct SettingsWindowTests {
  @Test func `destinations follow the settled order`() {
    #expect(
      SettingsDestination.allCases == [.settings, .history, .dictionary, .profiles, .models],
    )
  }
}
