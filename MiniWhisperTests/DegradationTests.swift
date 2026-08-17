import ASREngine
import AudioCapture
@testable import MiniWhisper
import Testing

// MARK: - DegradationTests

struct DegradationTests {
  // MARK: Internal

  @Test func `a healthy app is degraded by nothing`() {
    #expect(degradations() == [])
  }

  @Test func `model setup progress is not degraded`() {
    for readiness in [EngineReadiness.downloading(0.42), .compiling, .prewarming] {
      #expect(degradations(engineReadiness: readiness) == [])
    }
  }

  @Test func `an unrequested microphone is not a failure`() {
    #expect(degradations(micStatus: .undetermined) == [])
  }

  @Test(arguments: [MicPermissionStatus.denied, .restricted, .unknown])
  func `every unusable microphone status degrades`(status: MicPermissionStatus) {
    #expect(degradations(micStatus: status) == [.microphoneAccessDenied])
  }

  @Test func `a revoked accessibility grant degrades even while the tap still runs`() {
    #expect(degradations(accessibilityGranted: false) == [.accessibilityDenied])
  }

  @Test func `a revoked grant outranks the dead tap it caused`() {
    #expect(
      degradations(hotkeyTap: .dead, accessibilityGranted: false) == [.accessibilityDenied],
    )
    #expect(degradations(hotkeyTap: .dead) == [.hotkeyTapDead])
  }

  @Test func `model failures route through repair machinery`() {
    #expect(degradations(engineReadiness: .modelMissing) == [.modelMissing])
    #expect(degradations(engineReadiness: .failed("compile crashed")) == [.modelSetupFailed])
  }

  @Test func `every simultaneous failure is kept, worst first`() {
    #expect(
      degradations(
        hotkeyTap: .idle, micStatus: .denied, accessibilityGranted: false,
        engineReadiness: .modelMissing,
      ) == [.accessibilityDenied, .microphoneAccessDenied, .modelMissing],
    )
  }

  @Test func `a dead tap outranks the failures it is not`() {
    #expect(
      degradations(
        hotkeyTap: .dead, micStatus: .denied, accessibilityGranted: true,
        engineReadiness: .modelMissing,
      ) == [.hotkeyTapDead, .microphoneAccessDenied, .modelMissing],
    )
  }

  @Test func `a degradation says what pressing it does and why`() {
    let accessibility = Degradation.accessibilityDenied.presentation

    #expect(accessibility.title == "Grant Accessibility Access…")
    #expect(accessibility.reason == "Required to start dictation and paste text")
  }

  // MARK: Private

  private func degradations(
    hotkeyTap: HotkeyTapStatus = .active, micStatus: MicPermissionStatus = .granted,
    accessibilityGranted: Bool = true, engineReadiness: EngineReadiness = .ready,
  ) -> [Degradation] {
    AppHealth(
      hotkeyTap: hotkeyTap, micStatus: micStatus, accessibilityGranted: accessibilityGranted,
      engineReadiness: engineReadiness,
    ).degradations
  }
}
