import AudioCapture
@testable import MiniWhisper
import Testing

struct AgentDriveabilitySceneTests {
  @Test func `permission scenes advance one permission at A time`() {
    let inputMonitoring = AgentDriveabilityScene.onboardingPermissionsInputMonitoring.initialState
      .onboarding
    let microphone = AgentDriveabilityScene.onboardingPermissionsMicrophone.initialState.onboarding
    let pasteAccess = AgentDriveabilityScene.onboardingPermissionsPasteAccess.initialState
      .onboarding

    #expect(inputMonitoring.activePermission == .inputMonitoring)
    #expect(microphone.snapshot.permissions.hasInputMonitoringPermission)
    #expect(microphone.snapshot.permissions.microphoneStatus == .undetermined)
    #expect(microphone.activePermission == .microphone)
    #expect(pasteAccess.snapshot.permissions.microphoneStatus == .granted)
    #expect(!pasteAccess.snapshot.permissions.hasPasteAccess)
    #expect(pasteAccess.activePermission == .pasteAccess)
  }
}
