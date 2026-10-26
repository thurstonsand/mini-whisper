import AppSettings
import ASREngine
import AudioCapture
import ComposableArchitecture
import Foundation
@testable import MiniWhisper
import ModelLibrary
import Testing
import TranscriptCleanup

@MainActor struct ModelSetupTests {
  // MARK: Internal

  @Test func `a missing model is installed in place rather than reopening onboarding`() async {
    let consents = SynchronousCounter()
    let (readiness, continuation) = AsyncStream.makeStream(of: EngineReadiness.self)
    let store = TestStore(initialState: state(engineReadiness: .modelMissing)) {
      AppFeature()
    } withDependencies: {
      $0.modelDownloadConsent.markConsented = { consents.increment() }
      $0.asrEngine.installAndPrepare = { _ in readiness }
    }

    await store.send(.repairRequested(.modelMissing)) {
      $0.$health.withLock { $0.engineReadiness = .downloading(0) }
    }
    #expect(consents.value == 1)

    continuation.yield(.downloading(0.5))
    await store.receive(.engineReadinessUpdated(.parakeet, .downloading(0.5))) {
      $0.$health.withLock { $0.engineReadiness = .downloading(0.5) }
    }
    continuation.yield(.compiling)
    await store.receive(.engineReadinessUpdated(.parakeet, .compiling)) {
      $0.$health.withLock { $0.engineReadiness = .compiling }
    }
    continuation.yield(.ready)
    await store.receive(.engineReadinessUpdated(.parakeet, .ready)) {
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
      $0.asrEngine.installAndPrepare = { _ in
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
    await store.receive(.engineReadinessUpdated(.parakeet, .ready)) {
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
      $0.asrEngine.installAndPrepare = { _ in
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
      $0.asrEngine.installAndPrepare = { _ in
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
      $0.asrEngine.installAndPrepare = { _ in
        Issue.record("A download started without durable consent")
        return AsyncStream { $0.finish() }
      }
    }

    // Consent is recorded synchronously, so the failure can reach the shared health before the
    // repair itself is asserted; what matters is where the readiness ends up.
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.repairRequested(.modelMissing))
    await store.receive(.modelDownloadConsentRecordingFailed("disk full"))
    #expect(
      store.state.health.engineReadiness == .failed("Could not record download consent: disk full"),
    )
    #expect(store.state.health.degradations == [.modelSetupFailed])
  }

  @Test func `a consented model resumes at startup with onboarding long finished`() async {
    let readiness = EngineReadiness.modelMissing
    let installs = SynchronousCounter()
    let store = TestStore(initialState: AppFeature.State()) { AppFeature() } withDependencies: {
      $0.modelDownloadConsent.markConsented = {}
      $0.accessibilityPermission.hasPermission = { true }
      $0.hotkeyListener.events = { _ in AsyncStream { $0.finish() } }
      $0.asrEngine.installAndPrepare = { _ in
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
          engineReadiness: readiness,
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
      $0.asrEngine.installAndPrepare = { _ in
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

  /// Downloads are independent of the profile choice: choosing another card starts and stops
  /// nothing, and the download that was running reports to the end.
  @Test func `switching profiles mid-download leaves the download running`() async {
    let (readiness, continuation) = AsyncStream.makeStream(of: EngineReadiness.self)
    let store = TestStore(initialState: state(engineReadiness: .modelMissing)) {
      AppFeature()
    } withDependencies: {
      $0.modelDownloadConsent.markConsented = {}
      $0.asrEngine.installAndPrepare = { _ in readiness }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.repairRequested(.modelMissing))
    await store.send(.settingsWindow(.profiles(.profileSelected(.cerebras))))
    continuation.yield(.downloading(0.5))
    await store.receive(.engineReadinessUpdated(.parakeet, .downloading(0.5)))
    continuation.yield(.ready)
    await store.receive(.engineReadinessUpdated(.parakeet, .ready))
    continuation.finish()
    await store.finish()

    #expect(store.state.settings.profiles.active == .cerebras)
    #expect(store.state.health.engineReadiness == .ready)
  }

  /// The engine holds the model's files open; it lets go before they are deleted, and the app
  /// says plainly that nothing can be transcribed until the ordinary repair downloads it again.
  @Test func `deleting the active profile's model unloads the engine first`() async {
    let calls = TestBox<[String]>([])
    let store = TestStore(initialState: state(engineReadiness: .ready)) {
      AppFeature()
    } withDependencies: {
      $0.asrEngine.unload = { calls.value.append("unload \($0.shortName)") }
      $0.modelLibrary.delete = { calls.value.append("delete \($0.rawValue)") }
    }
    // The shared health moves inside the effect, before the send returns; what matters is where
    // it ends up and in what order the engine and the library were asked.
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.settingsWindow(.models(.delegate(.deleteAsset(.parakeet)))))
    await store.receive(.engineReadinessUpdated(.parakeet, .modelMissing))
    await store.finish()

    #expect(calls.value == ["unload Parakeet v2", "delete parakeet"])
    #expect(store.state.health.degradations == [.modelMissing])
  }

  @Test func `a deletion that fails is said in the pane`() async {
    let store = TestStore(initialState: state(engineReadiness: .ready)) {
      AppFeature()
    } withDependencies: {
      $0.asrEngine.unload = { _ in }
      $0.modelLibrary.delete = { _ in throw ConsentFailure() }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.settingsWindow(.models(.delegate(.deleteAsset(.gate)))))
    await store.receive(.settingsWindow(.models(.assetDeletionFailed("disk full"))))
    await store.finish()

    #expect(store.state.settingsWindow.models.assetFailure == "Couldn’t delete the model.")
  }

  /// The welcome button is consent for the whole profile, so Offline's cleanup model downloads
  /// beside the engine's rather than waiting to be asked for in the pane.
  @Test func `consent for offline downloads its cleanup model beside the engine`() async {
    var initial = state(engineReadiness: .modelMissing)
    initial.$settings.withLock { $0.profiles.active = .offline }
    let installed = TestBox<[ModelAsset]>([])
    let engines = TestBox<[SpeechEngine]>([])
    let store = TestStore(initialState: initial) {
      AppFeature()
    } withDependencies: {
      $0.modelDownloadConsent.isConsented = { false }
      $0.modelDownloadConsent.markConsented = {}
      $0.modelLibrary.isInstalled = { _ in false }
      $0.modelLibrary.install = { installed.value.append($0) }
      $0.cleanup.prepareLocal = {}
      $0.asrEngine.installAndPrepare = { engine in
        engines.value.append(engine)
        return AsyncStream { $0.finish() }
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.onboarding(.delegate(.setupModelRequested)))
    await store.finish()

    #expect(engines.value == [.parakeet])
    #expect(installed.value == [.s1Mini])
  }

  /// S1-mini is no engine's model, so its Download installs it directly rather than through
  /// model setup, and Offline warms it the moment it lands.
  @Test func `downloading the cleanup model installs it and warms it for offline`() async {
    var settings = MiniWhisperSettings.defaults
    settings.profiles.active = .offline
    var initial = state(engineReadiness: .ready)
    initial.$settings.withLock { $0 = settings }
    let installed = TestBox<[ModelAsset]>([])
    let prepared = TestBox<Int>(0)
    let store = TestStore(initialState: initial) {
      AppFeature()
    } withDependencies: {
      $0.modelLibrary.install = { installed.value.append($0) }
      $0.cleanup.prepareLocal = { prepared.value += 1 }
      $0.asrEngine.installAndPrepare = { _ in
        Issue.record("A cleanup model is never the engine's setup")
        return AsyncStream { $0.finish() }
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.settingsWindow(.models(.delegate(.downloadAsset(.s1Mini)))))
    await store.finish()

    #expect(installed.value == [.s1Mini])
    #expect(prepared.value == 1)
  }

  /// The Keychain is what says whether the profile can clean, so a key saved in the pane lifts
  /// the degradation and choosing a profile without one raises it.
  @Test func `the active factory profile's cleanup key decides the degradation`() async {
    let keys = TestBox<[CredentialSlot: String]>([:])
    let store = TestStore(initialState: state(engineReadiness: .ready)) {
      AppFeature()
    } withDependencies: {
      $0.keychain.read = { keys.value[$0] }
      $0.asrEngine.prepareInstalled = { _ in AsyncStream { $0.finish() } }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.settingsWindow(.profiles(.profileSelected(.cerebras))))
    #expect(store.state.health.missingCleanupKey == .cerebras)

    let slot = CredentialSlot(profile: .cerebras, provider: .cerebras)
    keys.value[slot] = "csk-key"
    await store.send(.settingsWindow(.profiles(.delegate(.keysStored([slot])))))
    #expect(store.state.health.missingCleanupKey == nil)

    // Custom's cleanup is optional, so its missing key never stops a raw dictation.
    await store.send(.settingsWindow(.profiles(.profileSelected(.custom))))
    #expect(store.state.health.missingCleanupKey == nil)
  }

  /// Choosing Most accurate asks Scribe whether it can hear, and the Parakeet download that was
  /// running keeps reporting to Parakeet: none of it reaches the engine now in use.
  @Test func `a download that outlives its profile never speaks for the new one`() async {
    let (parakeet, parakeetUpdates) = AsyncStream.makeStream(of: EngineReadiness.self)
    let sounds = TestBox<Int>(0)
    let store = TestStore(initialState: state(engineReadiness: .modelMissing)) {
      AppFeature()
    } withDependencies: {
      $0.modelDownloadConsent.markConsented = {}
      $0.asrEngine.installAndPrepare = { engine in
        #expect(engine == .parakeet)
        return parakeet
      }
      $0.asrEngine.prepareInstalled = { engine in
        AsyncStream {
          $0.yield(engine == .scribe ? .credentialMissing : .failed("network down"))
          $0.finish()
        }
      }
      // Only the engine's key is missing: the degradation under test is the engine's alone.
      $0.keychain.read = { $0.provider == .elevenlabs ? nil : "sk-test" }
      $0.cleanup.listModels = { _, _ in .cancelled }
      $0.sounds.play = { _ in sounds.value += 1 }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.repairRequested(.modelMissing))
    await store.send(.settingsWindow(.profiles(.profileSelected(.accurate))))
    await store.receive(.engineReadinessUpdated(.scribe, .credentialMissing))
    #expect(store.state.health.engine == .scribe)
    #expect(store.state.health.degradations == [.engineKeyMissing])

    parakeetUpdates.yield(.failed("network down"))
    await store.receive(.engineReadinessUpdated(.parakeet, .failed("network down")))
    parakeetUpdates.finish()
    await store.finish()

    #expect(store.state.health.engineReadiness == .credentialMissing)
    #expect(store.state.health.readinessByEngine[.parakeet] == .failed("network down"))
    #expect(sounds.value == 0)

    await store.send(.settingsWindow(.profiles(.profileSelected(.haiku))))
    await store.receive(.engineReadinessUpdated(.parakeet, .failed("network down")))
    #expect(store.state.health.degradations == [.modelSetupFailed])
    #expect(sounds.value == 0)
  }

  /// A refused key is the profile needing setup again, not the engine breaking.
  @Test func `a key the service refuses leaves the profile needing a key`() async {
    var state = state(engineReadiness: .ready)
    state.$settings.withLock { $0.profiles.active = .accurate }
    state.$health.withLock {
      $0.engine = .scribe
      $0.engineReadiness = .ready
    }
    let store = TestStore(initialState: state) { AppFeature() } withDependencies: {
      $0.asrEngine.submit = { engine, _, _ in
        #expect(engine == .scribe)
        throw ASREngineError.credentialRejected
      }
      $0.date.now = Date(timeIntervalSince1970: 1000)
      $0.uuid = .incrementing
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.recording(.delegate(.completed(CanonicalRecording(samples: [0.1])))))
    await store.receive(.engineReadinessUpdated(.scribe, .credentialMissing))
    await store.receive(.transcriptionFailed(
      0,
      ASREngineError.credentialRejected.localizedDescription,
    ))
    await store.finish()

    #expect(store.state.health.degradations == [.engineKeyMissing])
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
