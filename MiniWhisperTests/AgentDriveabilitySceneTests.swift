import AudioCapture
@testable import MiniWhisper
import Testing

struct AgentDriveabilitySceneTests {
  @Test func `window scenes select one window`() {
    #expect(
      AgentDriveabilityScene.settings.presentedWindow
        == .settings(.settings, initialFocus: nil),
    )
    #expect(
      AgentDriveabilityScene.settingsShortcutsKeyboard.presentedWindow
        == .settings(.settings, initialFocus: .detail),
    )
    #expect(
      AgentDriveabilityScene.settingsShortcutsKeyboard.initialState.settingsWindow.interaction.mode
        == .keyboard,
    )
    #expect(AgentDriveabilityScene.about.presentedWindow == .about)
    #expect(AgentDriveabilityScene.menuHealthy.presentedWindow == nil)
  }

  @Test func `permission scenes advance one permission at A time`() {
    let microphone = AgentDriveabilityScene.onboardingPermissionsMicrophone.initialState.onboarding
    let accessibility = AgentDriveabilityScene.onboardingPermissionsAccessibility.initialState
      .onboarding

    #expect(microphone.snapshot.permissions.microphoneStatus == .undetermined)
    #expect(microphone.activePermission == .microphone)
    #expect(accessibility.snapshot.permissions.microphoneStatus == .granted)
    #expect(!accessibility.snapshot.permissions.hasAccessibilityPermission)
    #expect(accessibility.activePermission == .accessibility)
  }
}
