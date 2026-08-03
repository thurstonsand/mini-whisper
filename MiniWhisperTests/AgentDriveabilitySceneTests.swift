import AudioCapture
@testable import MiniWhisper
import Testing

struct AgentDriveabilitySceneTests {
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
