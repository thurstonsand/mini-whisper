import AudioCapture
import Testing

@testable import MiniWhisper

@Suite struct AgentDriveabilitySceneTests {
  @Test func permissionScenesAdvanceOnePermissionAtATime() {
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
