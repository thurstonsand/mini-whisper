import ASREngine
import AudioCapture
import ComposableArchitecture
import Foundation
@testable import MiniWhisper
import Testing

@MainActor struct ModelSetupTests {
  // MARK: Internal

  @Test func `a missing model is installed in place rather than reopening onboarding`() async {
    let consents = SynchronousCounter()
    let (readiness, continuation) = AsyncStream.makeStream(of: EngineReadiness.self)
    let store = TestStore(initialState: state(engineReadiness: .modelMissing)) {
      AppFeature()
    } withDependencies: {
      $0.modelDownloadConsent.markConsented = { consents.increment() }
      $0.asrEngine.installAndPrepare = { readiness }
    }

    await store.send(.repairRequested(.modelMissing)) {
      $0.$health.withLock { $0.engineReadiness = .downloading(0) }
    }
    #expect(consents.value == 1)

    continuation.yield(.downloading(0.5))
    await store.receive(.engineReadinessUpdated(.downloading(0.5))) {
      $0.$health.withLock { $0.engineReadiness = .downloading(0.5) }
    }
    continuation.yield(.compiling)
    await store.receive(.engineReadinessUpdated(.compiling)) {
      $0.$health.withLock { $0.engineReadiness = .compiling }
    }
    continuation.yield(.ready)
    await store.receive(.engineReadinessUpdated(.ready)) {
      $0.$health.withLock { $0.engineReadiness = .ready }
    }
    continuation.finish()
    await store.finish()

    #expect(!store.state.onboarding.isPresented)
    #expect(store.state.health.degradations.isEmpty)
  }

  @Test func `a second request before the first reports anything is ignored`() async {
    let installs = SynchronousCounter()
    let (readiness, continuation) = AsyncStream.makeStream(of: EngineReadiness.self)
    let store = TestStore(initialState: state(engineReadiness: .modelMissing)) {
      AppFeature()
    } withDependencies: {
      $0.modelDownloadConsent.markConsented = {}
      $0.asrEngine.installAndPrepare = {
        installs.increment()
        return readiness
      }
    }

    await store.send(.repairRequested(.modelMissing)) {
      $0.$health.withLock { $0.engineReadiness = .downloading(0) }
    }
    await store.send(.repairRequested(.modelMissing))
    #expect(installs.value == 1)

    continuation.yield(.ready)
    await store.receive(.engineReadinessUpdated(.ready)) {
      $0.$health.withLock { $0.engineReadiness = .ready }
    }
    continuation.finish()
    await store.finish()
  }

  @Test func `a stale request against a ready consented engine does nothing`() async {
    let store = TestStore(initialState: state(engineReadiness: .ready)) {
      AppFeature()
    } withDependencies: {
      $0.modelDownloadConsent.isConsented = { true }
      $0.asrEngine.installAndPrepare = {
        Issue.record("A ready engine was asked to install")
        return AsyncStream { $0.finish() }
      }
    }

    await store.send(.repairRequested(.modelMissing))
  }

  @Test func `welcome records missing consent without reinstalling a ready model`() async {
    let consents = SynchronousCounter()
    var state = state(engineReadiness: .ready)
    state.onboarding.isPresented = true
    state.onboarding.isShowingWelcome = true
    state.onboarding.isRecordingModelDownloadConsent = true
    let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
      $0.modelDownloadConsent.isConsented = { false }
      $0.modelDownloadConsent.markConsented = { consents.increment() }
      $0.asrEngine.installAndPrepare = {
        Issue.record("A ready engine was asked to install")
        return AsyncStream { $0.finish() }
      }
    }

    await store.send(.onboarding(.delegate(.setupModelRequested)))
    await store.receive(.modelDownloadConsentRecorded)
    await store.receive(.onboarding(.modelDownloadConsented)) {
      $0.onboarding.snapshot.hasModelDownloadConsent = true
      $0.onboarding.isShowingWelcome = false
      $0.onboarding.isRecordingModelDownloadConsent = false
    }
    #expect(consents.value == 1)
    #expect(store.state.health.engineReadiness == .ready)
  }

  @Test func `a consent that cannot be recorded fails the setup instead of downloading`() async {
    let store = TestStore(initialState: state(engineReadiness: .modelMissing)) {
      AppFeature()
    } withDependencies: {
      $0.modelDownloadConsent.markConsented = { throw ConsentFailure() }
      $0.asrEngine.installAndPrepare = {
        Issue.record("A download started without durable consent")
        return AsyncStream { $0.finish() }
      }
    }

    await store.send(.repairRequested(.modelMissing)) {
      $0.$health.withLock { $0.engineReadiness = .downloading(0) }
    }
    await store.receive(.modelDownloadConsentRecordingFailed("disk full")) {
      $0.$health.withLock {
        $0.engineReadiness = .failed("Could not record download consent: disk full")
      }
    }
    #expect(store.state.health.degradations == [.modelSetupFailed])
  }

  @Test func `a consented model resumes at startup with onboarding long finished`() async {
    let installs = SynchronousCounter()
    let store = TestStore(initialState: AppFeature.State()) { AppFeature() } withDependencies: {
      $0.modelDownloadConsent.markConsented = {}
      $0.accessibilityPermission.hasPermission = { true }
      $0.hotkeyListener.events = { _ in AsyncStream { $0.finish() } }
      $0.asrEngine.installAndPrepare = {
        installs.increment()
        return AsyncStream { $0.finish() }
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(
      .startupResolved(
        AppFeature.StartupFacts(
          onboardingCompleted: true, modelDownloadConsented: true,
          permissions: OnboardingPermissionStatuses(
            microphoneStatus: .granted, hasAccessibilityPermission: true,
          ),
          engineReadiness: .modelMissing,
        ),
      ),
    )
    #expect(installs.value == 1)
    #expect(!store.state.onboarding.isPresented)
    await store.finish()
  }

  @Test(arguments: [
    (consented: false, readiness: EngineReadiness.modelMissing),
    (consented: true, readiness: EngineReadiness.failed("compile crashed")),
    (consented: true, readiness: EngineReadiness.ready),
  ])
  func `startup installs nothing it was not asked to`(
    scenario: (consented: Bool, readiness: EngineReadiness),
  ) async {
    let store = TestStore(initialState: AppFeature.State()) { AppFeature() } withDependencies: {
      $0.accessibilityPermission.hasPermission = { true }
      $0.hotkeyListener.events = { _ in AsyncStream { $0.finish() } }
      $0.asrEngine.installAndPrepare = {
        Issue.record("Startup started an install for \(scenario)")
        return AsyncStream { $0.finish() }
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(
      .startupResolved(
        AppFeature.StartupFacts(
          onboardingCompleted: true, modelDownloadConsented: scenario.consented,
          permissions: OnboardingPermissionStatuses(
            microphoneStatus: .granted, hasAccessibilityPermission: true,
          ),
          engineReadiness: scenario.readiness,
        ),
      ),
    )
    await store.finish()
  }

  // MARK: Private

  private struct ConsentFailure: Error, LocalizedError {
    var errorDescription: String? {
      "disk full"
    }
  }

  private func state(engineReadiness: EngineReadiness) -> AppFeature.State {
    var health = AppHealth.healthy
    health.engineReadiness = engineReadiness
    var state = AppFeature.State(health: Shared(value: health))
    state.onboardingCompleted = true
    return state
  }
}
