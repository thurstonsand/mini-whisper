import ASREngine
import AudioCapture
import ComposableArchitecture
import Foundation
@testable import MiniWhisper
import Testing

// MARK: - OnboardingStepDerivationTests

struct OnboardingStepDerivationTests {
  @Test func `every permission must land before setup leaves the permissions step`() {
    var snapshot = OnboardingSnapshot(
      permissions: OnboardingPermissionStatuses(
        hasInputMonitoringPermission: false, microphoneStatus: .undetermined,
        hasPasteAccess: false,
      ),
      engineReadiness: .modelMissing, hasModelDownloadConsent: false, isCompleted: false,
    )
    #expect(OnboardingStep.derive(from: snapshot) == .permissions)

    snapshot.permissions.hasInputMonitoringPermission = true
    #expect(OnboardingStep.derive(from: snapshot) == .permissions)

    snapshot.permissions.microphoneStatus = .granted
    #expect(OnboardingStep.derive(from: snapshot) == .permissions)

    snapshot.permissions.hasPasteAccess = true
    #expect(OnboardingStep.derive(from: snapshot) == .model)

    snapshot.engineReadiness = .ready
    #expect(OnboardingStep.derive(from: snapshot) == .tryIt)

    snapshot.isCompleted = true
    #expect(OnboardingStep.derive(from: snapshot) == .ready)
  }

  @Test func `only the first ungranted permission owns the action`() {
    var state = OnboardingFeature.State()
    #expect(state.activePermission == .inputMonitoring)
    #expect(state.canRequest(.inputMonitoring))
    #expect(!state.canRequest(.microphone))
    #expect(!state.canRequest(.pasteAccess))

    state.snapshot.permissions.hasInputMonitoringPermission = true
    #expect(state.activePermission == .microphone)
    #expect(state.canRequest(.microphone))
    #expect(!state.canRequest(.pasteAccess))

    state.snapshot.permissions.microphoneStatus = .granted
    #expect(state.activePermission == .pasteAccess)
    #expect(state.canRequest(.pasteAccess))

    state.snapshot.permissions.hasPasteAccess = true
    #expect(state.activePermission == nil)
  }

  @Test(arguments: [MicPermissionStatus.denied, .restricted, .undetermined, .unknown])
  func `every non granted microphone state stops at permissions`(_ status: MicPermissionStatus) {
    let snapshot = OnboardingSnapshot(
      permissions: OnboardingPermissionStatuses(
        hasInputMonitoringPermission: true, microphoneStatus: status, hasPasteAccess: true,
      ),
      engineReadiness: .ready, hasModelDownloadConsent: true, isCompleted: true,
    )

    #expect(OnboardingStep.derive(from: snapshot) == .permissions)
    #expect(!snapshot.permissions.isGranted(.microphone))
  }
}

// MARK: - OnboardingFeatureTests

@MainActor struct OnboardingFeatureTests {
  // MARK: Internal

  @Test func `untouched first run waits for download consent`() async {
    let (readiness, continuation) = AsyncStream.makeStream(of: EngineReadiness.self)
    let installs = SynchronousCounter()
    let consents = SynchronousCounter()
    let snapshot = OnboardingSnapshot(
      permissions: OnboardingPermissionStatuses(
        hasInputMonitoringPermission: false, microphoneStatus: .undetermined,
        hasPasteAccess: false,
      ),
      engineReadiness: .modelMissing, hasModelDownloadConsent: false, isCompleted: false,
    )
    let store = TestStore(initialState: OnboardingFeature.State()) {
      OnboardingFeature()
    } withDependencies: {
      $0.continuousClock = TestClock()
      $0.modelDownloadConsent.markConsented = { consents.increment() }
      $0.asrEngine.installAndPrepare = {
        installs.increment()
        return readiness
      }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.present(snapshot)) {
      $0.isPresented = true
      $0.snapshot = snapshot
      $0.isShowingWelcome = true
    }
    #expect(installs.value == 0)

    await store.send(.downloadModel) { $0.isRecordingModelDownloadConsent = true }
    await store.receive(.modelDownloadConsented) {
      $0.snapshot.hasModelDownloadConsent = true
      $0.isShowingWelcome = false
      $0.isRecordingModelDownloadConsent = false
    }
    #expect(consents.value == 1)
    #expect(installs.value == 1)

    continuation.yield(.downloading(0.25))
    await store.receive(.delegate(.engineReadinessUpdated(.downloading(0.25))))
    await store.send(.engineReadinessUpdated(.downloading(0.25))) {
      $0.snapshot.engineReadiness = .downloading(0.25)
    }
    continuation.finish()
    await store.send(.permissionStatusesObserved(observation(grantedPermissionStatuses)))
    await store.finish()
  }

  @Test func `consented relaunch skips welcome and resumes model setup`() async {
    let (readiness, continuation) = AsyncStream.makeStream(of: EngineReadiness.self)
    let snapshot = OnboardingSnapshot(
      permissions: OnboardingPermissionStatuses(
        hasInputMonitoringPermission: true, microphoneStatus: .undetermined, hasPasteAccess: false,
      ),
      engineReadiness: .modelMissing, hasModelDownloadConsent: true, isCompleted: false,
    )
    let store = TestStore(initialState: OnboardingFeature.State()) {
      OnboardingFeature()
    } withDependencies: {
      $0.continuousClock = TestClock()
      $0.asrEngine.installAndPrepare = { readiness }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.present(snapshot)) {
      $0.isPresented = true
      $0.snapshot = snapshot
    }
    #expect(!store.state.isShowingWelcome)
    continuation.yield(.downloading(0.25))
    await store.receive(.delegate(.engineReadinessUpdated(.downloading(0.25))))
    await store.send(.engineReadinessUpdated(.downloading(0.25))) {
      $0.snapshot.engineReadiness = .downloading(0.25)
    }
    continuation.finish()
    await store.send(.permissionStatusesObserved(observation(grantedPermissionStatuses)))
    await store.finish()
  }

  @Test func `polling carries every visible grant to the model step`() async {
    let clock = TestClock()
    let statuses = SynchronousStatuses()
    let store = TestStore(initialState: OnboardingFeature.State()) {
      OnboardingFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.hotkeyListener.hasInputMonitoringPermission = {
        statuses.value.hasInputMonitoringPermission
      }
      $0.microphonePermission.status = { statuses.value.microphoneStatus }
      $0.delivery.hasPasteAccess = { statuses.value.hasPasteAccess }
      $0.asrEngine.installAndPrepare = { AsyncStream { $0.finish() } }
    }

    let initialSnapshot = OnboardingSnapshot(
      permissions: OnboardingPermissionStatuses(
        hasInputMonitoringPermission: false, microphoneStatus: .undetermined,
        hasPasteAccess: false,
      ),
      engineReadiness: .modelMissing, hasModelDownloadConsent: true, isCompleted: false,
    )
    await store.send(.present(initialSnapshot)) {
      $0.isPresented = true
      $0.snapshot = initialSnapshot
    }

    statuses.withValue { $0.hasInputMonitoringPermission = true }
    await clock.advance(by: .seconds(1))
    await store.receive(.refreshPermissionStatuses)
    await store.receive(.permissionStatusesObserved(observation(statuses.value))) {
      $0.snapshot.permissions.hasInputMonitoringPermission = true
    }
    await store.receive(.delegate(.permissionsUpdated(statuses.value)))
    #expect(store.state.step == .permissions)

    statuses.withValue { $0.microphoneStatus = .granted }
    await clock.advance(by: .seconds(1))
    await store.receive(.refreshPermissionStatuses)
    await store.receive(.permissionStatusesObserved(observation(statuses.value))) {
      $0.snapshot.permissions.microphoneStatus = .granted
    }
    await store.receive(.delegate(.permissionsUpdated(statuses.value)))
    #expect(store.state.step == .permissions)

    statuses.withValue { $0.hasPasteAccess = true }
    await clock.advance(by: .seconds(1))
    await store.receive(.refreshPermissionStatuses)
    await store.receive(.permissionStatusesObserved(observation(statuses.value))) {
      $0.snapshot.permissions.hasPasteAccess = true
    }
    await store.receive(.delegate(.permissionsUpdated(statuses.value)))
    #expect(store.state.step == .model)
  }

  @Test func `polling defers paste access until the input monitoring prompt returns`() async {
    let clock = TestClock()
    let pasteProbes = SynchronousCounter()
    let requests = SynchronousCounter()
    let snapshot = OnboardingSnapshot(
      permissions: OnboardingPermissionStatuses(
        hasInputMonitoringPermission: false, microphoneStatus: .undetermined,
        hasPasteAccess: false,
      ),
      engineReadiness: .modelMissing, hasModelDownloadConsent: false, isCompleted: false,
    )
    let store = TestStore(initialState: OnboardingFeature.State()) {
      OnboardingFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.hotkeyListener.hasInputMonitoringPermission = { false }
      $0.hotkeyListener.requestInputMonitoringPermission = {
        requests.increment()
        return false
      }
      $0.microphonePermission.status = { .undetermined }
      $0.workspace.applicationLocation = { applicationLocation }
      $0.delivery.hasPasteAccess = {
        pasteProbes.increment()
        return false
      }
    }

    await store.send(.present(snapshot)) {
      $0.isPresented = true
      $0.snapshot = snapshot
      $0.isShowingWelcome = true
    }
    await clock.advance(by: .seconds(1))
    await store.receive(.refreshPermissionStatuses)
    await store.receive(
      .permissionStatusesObserved(
        OnboardingPermissionObservation(
          hasInputMonitoringPermission: false, microphoneStatus: .undetermined,
          hasPasteAccess: nil,
        ),
      ),
    )
    #expect(pasteProbes.value == 0)

    await store.send(.requestPermission(.inputMonitoring)) {
      $0.requestingPermission = .inputMonitoring
      $0.pendingSystemPermissionPrompt = .inputMonitoring
      $0.requestedPermissions = [.inputMonitoring]
    }
    await store.receive(.inputMonitoringPermissionRequested(false)) {
      $0.requestingPermission = nil
      $0.applicationPath = applicationLocation.path(percentEncoded: false)
    }
    await store.send(.requestPermission(.inputMonitoring))
    #expect(requests.value == 1)

    await clock.advance(by: .seconds(1))
    await store.send(.refreshPermissionStatuses)
    #expect(pasteProbes.value == 0)

    await store.send(.applicationBecameActive) { $0.pendingSystemPermissionPrompt = nil }
    await store.receive(
      .permissionStatusesObserved(
        OnboardingPermissionObservation(
          hasInputMonitoringPermission: false, microphoneStatus: .undetermined,
          hasPasteAccess: false,
        ),
      ),
    )
    #expect(pasteProbes.value == 1)

    await store.send(.permissionStatusesObserved(observation(grantedPermissionStatuses))) {
      $0.snapshot.permissions = grantedPermissionStatuses
    }
    await store.receive(.delegate(.permissionsUpdated(grantedPermissionStatuses)))
  }

  @Test func `paste access prompt suspends checks and cannot be requested twice`() async {
    let clock = TestClock()
    let probes = SynchronousCounter()
    let requests = SynchronousCounter()
    var state = presentedPermissionsState()
    state.snapshot.permissions.hasInputMonitoringPermission = true
    state.snapshot.permissions.microphoneStatus = .granted
    let store = TestStore(initialState: state) {
      OnboardingFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.hotkeyListener.hasInputMonitoringPermission = { true }
      $0.microphonePermission.status = { .granted }
      $0.delivery.hasPasteAccess = {
        probes.increment()
        return false
      }
      $0.delivery.requestPasteAccess = {
        requests.increment()
        return false
      }
    }

    await store.send(.requestPermission(.pasteAccess)) {
      $0.requestingPermission = .pasteAccess
      $0.pendingSystemPermissionPrompt = .pasteAccess
      $0.requestedPermissions = [.pasteAccess]
    }
    await store.receive(.pasteAccessRequested(false)) { $0.requestingPermission = nil }
    await store.send(.requestPermission(.pasteAccess))
    await store.send(.refreshPermissionStatuses)
    #expect(requests.value == 1)
    #expect(probes.value == 0)

    await store.send(.applicationBecameActive) { $0.pendingSystemPermissionPrompt = nil }
    await store.receive(
      .permissionStatusesObserved(
        OnboardingPermissionObservation(
          hasInputMonitoringPermission: true, microphoneStatus: .granted, hasPasteAccess: false,
        ),
      ),
    )
    #expect(probes.value == 1)

    await store.send(.permissionStatusesObserved(observation(grantedPermissionStatuses))) {
      $0.snapshot.permissions = grantedPermissionStatuses
    }
    await store.receive(.delegate(.permissionsUpdated(grantedPermissionStatuses)))
  }

  @Test func `an unfulfilled input monitoring request pivots to system settings`() async {
    let opened = SynchronousValues()
    let store = TestStore(initialState: presentedPermissionsState()) {
      OnboardingFeature()
    } withDependencies: {
      $0.continuousClock = TestClock()
      $0.hotkeyListener.hasInputMonitoringPermission = { false }
      $0.hotkeyListener.requestInputMonitoringPermission = { false }
      $0.workspace.applicationLocation = { applicationLocation }
      $0.workspace.open = { url in opened.append(url) }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.requestPermission(.inputMonitoring)) {
      $0.requestingPermission = .inputMonitoring
      $0.pendingSystemPermissionPrompt = .inputMonitoring
      $0.requestedPermissions = [.inputMonitoring]
    }
    await store.receive(.inputMonitoringPermissionRequested(false)) {
      $0.requestingPermission = nil
      $0.applicationPath = applicationLocation.path(percentEncoded: false)
    }
    #expect(store.state.needsSystemSettings(for: .inputMonitoring))

    await store.send(.openSystemSettings(.inputMonitoring))
    await store.send(.permissionStatusesObserved(observation(grantedPermissionStatuses)))
    await store.finish()
    #expect(opened.values == [SystemSettingsPane.inputMonitoring])
  }

  @Test func `an unfulfilled input monitoring request asks for A manual add`() async {
    let copied = SynchronousStrings()
    let store = TestStore(initialState: presentedPermissionsState()) {
      OnboardingFeature()
    } withDependencies: {
      $0.continuousClock = TestClock()
      $0.hotkeyListener.hasInputMonitoringPermission = { false }
      $0.hotkeyListener.requestInputMonitoringPermission = { false }
      $0.microphonePermission.status = { .undetermined }
      $0.workspace.applicationLocation = { applicationLocation }
      $0.delivery.hasPasteAccess = { false }
      $0.delivery.copy = { copied.append($0) }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    #expect(!store.state.needsManualInputMonitoringAdd)
    await store.send(.requestPermission(.inputMonitoring)) {
      $0.requestingPermission = .inputMonitoring
      $0.pendingSystemPermissionPrompt = .inputMonitoring
      $0.requestedPermissions = [.inputMonitoring]
    }
    // The request is still in flight, so any dialog macOS might be showing still owns the outcome.
    #expect(!store.state.needsManualInputMonitoringAdd)

    await store.receive(.inputMonitoringPermissionRequested(false)) {
      $0.requestingPermission = nil
      $0.applicationPath = applicationLocation.path(percentEncoded: false)
    }
    #expect(store.state.needsManualInputMonitoringAdd)
    #expect(store.state.needsRestart(for: .inputMonitoring))

    await store.send(.copyApplicationPath)
    await store.finish()
    #expect(copied.values == [applicationLocation.path(percentEncoded: false)])

    // Returning from System Settings must not retract the guidance.
    await store.send(.applicationBecameActive) { $0.pendingSystemPermissionPrompt = nil }
    #expect(store.state.needsManualInputMonitoringAdd)

    await store.send(.permissionStatusesObserved(observation(grantedPermissionStatuses))) {
      $0.snapshot.permissions = grantedPermissionStatuses
    }
    #expect(!store.state.needsManualInputMonitoringAdd)
  }

  @Test func `A late refusal cannot undo an observed input monitoring grant`() async {
    var state = presentedPermissionsState()
    state.requestedPermissions = [.inputMonitoring]
    state.requestingPermission = .inputMonitoring
    state.pendingSystemPermissionPrompt = .inputMonitoring
    let store = TestStore(initialState: state) {
      OnboardingFeature()
    } withDependencies: {
      $0.continuousClock = TestClock()
      $0.hotkeyListener.hasInputMonitoringPermission = { true }
      $0.microphonePermission.status = { .granted }
      $0.delivery.hasPasteAccess = { true }
      $0.workspace.applicationLocation = { applicationLocation }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.applicationBecameActive) { $0.pendingSystemPermissionPrompt = nil }
    await store.receive(.permissionStatusesObserved(observation(grantedPermissionStatuses))) {
      $0.snapshot.permissions = grantedPermissionStatuses
    }
    #expect(!store.state.needsManualInputMonitoringAdd)

    // The request that was still in flight finally answers, and its answer is the older truth.
    await store.send(.inputMonitoringPermissionRequested(false)) { $0.requestingPermission = nil }
    #expect(store.state.snapshot.permissions.hasInputMonitoringPermission)
    #expect(!store.state.needsManualInputMonitoringAdd)
    #expect(store.state.applicationPath.isEmpty)
    #expect(store.state.step == .model)
  }

  @Test func `A granted input monitoring request never asks for A manual add`() async {
    let store = TestStore(initialState: presentedPermissionsState()) {
      OnboardingFeature()
    } withDependencies: {
      $0.continuousClock = TestClock()
      $0.hotkeyListener.hasInputMonitoringPermission = { true }
      $0.hotkeyListener.requestInputMonitoringPermission = { true }
      $0.microphonePermission.status = { .undetermined }
      $0.delivery.hasPasteAccess = { false }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.requestPermission(.inputMonitoring)) {
      $0.requestingPermission = .inputMonitoring
      $0.pendingSystemPermissionPrompt = .inputMonitoring
      $0.requestedPermissions = [.inputMonitoring]
    }
    await store.receive(.inputMonitoringPermissionRequested(true)) {
      $0.requestingPermission = nil
      $0.pendingSystemPermissionPrompt = nil
      $0.snapshot.permissions.hasInputMonitoringPermission = true
    }
    #expect(!store.state.needsManualInputMonitoringAdd)
    #expect(!store.state.needsRestart(for: .inputMonitoring))
    #expect(store.state.applicationPath.isEmpty)

    await store.send(.applicationBecameActive)
    #expect(!store.state.needsManualInputMonitoringAdd)

    await store.send(.permissionStatusesObserved(observation(grantedPermissionStatuses))) {
      $0.snapshot.permissions = grantedPermissionStatuses
    }
  }

  @Test func `stale input monitoring offers an application restart`() async {
    let restarts = SynchronousCounter()
    var state = presentedPermissionsState()
    state.requestedPermissions = [.inputMonitoring]
    let store = TestStore(initialState: state) {
      OnboardingFeature()
    } withDependencies: {
      $0.workspace.relaunch = { restarts.increment() }
    }

    #expect(store.state.activePermission == .inputMonitoring)
    #expect(store.state.needsRestart(for: .inputMonitoring))
    await store.send(.restartApplication)
    await store.finish()
    #expect(restarts.value == 1)
  }

  @Test func `input monitoring grant uses the request endpoint`() async {
    let store = TestStore(initialState: presentedPermissionsState()) {
      OnboardingFeature()
    } withDependencies: {
      $0.continuousClock = TestClock()
      $0.hotkeyListener.requestInputMonitoringPermission = { true }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.requestPermission(.inputMonitoring)) {
      $0.requestingPermission = .inputMonitoring
      $0.pendingSystemPermissionPrompt = .inputMonitoring
      $0.requestedPermissions = [.inputMonitoring]
    }
    await store.receive(.inputMonitoringPermissionRequested(true)) {
      $0.requestingPermission = nil
      $0.pendingSystemPermissionPrompt = nil
      $0.snapshot.permissions.hasInputMonitoringPermission = true
    }
    await store.receive(.delegate(.permissionsUpdated(store.state.snapshot.permissions)))
    await store.send(.permissionStatusesObserved(observation(grantedPermissionStatuses)))
    await store.finish()
  }

  @Test func `an unmeasured paste status preserves the last observation`() async {
    var state = presentedPermissionsState()
    state.snapshot.permissions.hasPasteAccess = true
    let store = TestStore(initialState: state) { OnboardingFeature() }
    let updated = OnboardingPermissionStatuses(
      hasInputMonitoringPermission: false, microphoneStatus: .denied, hasPasteAccess: true,
    )

    await store.send(
      .permissionStatusesObserved(
        OnboardingPermissionObservation(
          hasInputMonitoringPermission: false, microphoneStatus: .denied, hasPasteAccess: nil,
        ),
      ),
    ) { $0.snapshot.permissions = updated }
    await store.receive(.delegate(.permissionsUpdated(updated)))
  }

  @Test func `an already queued observation cannot mutate A waiting prompt`() async {
    var state = presentedPermissionsState()
    state.requestingPermission = .inputMonitoring
    state.pendingSystemPermissionPrompt = .inputMonitoring
    state.requestedPermissions = [.inputMonitoring]
    let store = TestStore(initialState: state) { OnboardingFeature() }

    await store.send(
      .permissionStatusesObserved(
        OnboardingPermissionObservation(
          hasInputMonitoringPermission: false, microphoneStatus: .denied, hasPasteAccess: nil,
        ),
      ),
    )
    #expect(store.state.requestingPermission == .inputMonitoring)
    #expect(store.state.snapshot.permissions.microphoneStatus == .undetermined)
  }

  @Test func `sidebar navigation overrides the view without changing truth`() async {
    let clock = TestClock()
    let snapshot = modelSnapshot(readiness: .modelMissing)
    var state = OnboardingFeature.State()
    state.isPresented = true
    state.snapshot = snapshot
    let store = TestStore(initialState: state) {
      OnboardingFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.hotkeyListener.hasInputMonitoringPermission = { true }
      $0.microphonePermission.status = { .granted }
      $0.delivery.hasPasteAccess = { true }
    }

    await store.send(.navigate(.tryIt)) { $0.selectedStep = .tryIt }
    #expect(store.state.step == .model)
    #expect(store.state.visibleStep == .tryIt)

    await store.send(.navigate(.permissions)) { $0.selectedStep = .permissions }
    await store.receive(.permissionStatusesObserved(observation(snapshot.permissions)))
    #expect(store.state.isRevisitingPermissions)

    await store.send(.navigate(.model)) { $0.selectedStep = .model }
    await store.finish()
  }

  @Test func `a granted request flips the row immediately`() async {
    var state = presentedPermissionsState()
    state.snapshot.permissions.hasInputMonitoringPermission = true
    let store = TestStore(initialState: state) {
      OnboardingFeature()
    } withDependencies: {
      $0.continuousClock = TestClock()
      $0.microphonePermission.requestIfNeeded = { .granted }
    }

    await store.send(.requestPermission(.microphone)) {
      $0.requestingPermission = .microphone
      $0.pendingSystemPermissionPrompt = .microphone
      $0.requestedPermissions = [.microphone]
    }
    await store.receive(.microphonePermissionRequested(.granted)) {
      $0.requestingPermission = nil
      $0.pendingSystemPermissionPrompt = nil
      $0.snapshot.permissions.microphoneStatus = .granted
    }
    await store.receive(.delegate(.permissionsUpdated(store.state.snapshot.permissions)))
    #expect(!store.state.needsSystemSettings(for: .microphone))
    await store.send(.permissionStatusesObserved(observation(grantedPermissionStatuses))) {
      $0.snapshot.permissions = grantedPermissionStatuses
    }
    await store.receive(.delegate(.permissionsUpdated(grantedPermissionStatuses)))
  }

  @Test func `model setup reports download compile prewarm and ready`() async {
    let readiness = [EngineReadiness.downloading(0.4), .compiling, .prewarming, .ready]
    var state = OnboardingFeature.State()
    state.isPresented = true
    state.snapshot = modelSnapshot(readiness: .modelMissing)
    let store = TestStore(initialState: state) {
      OnboardingFeature()
    } withDependencies: {
      $0.asrEngine.installAndPrepare = {
        AsyncStream { continuation in
          for value in readiness {
            continuation.yield(value)
          }
          continuation.finish()
        }
      }
    }

    await store.send(.setupModel)
    for value in readiness {
      await store.receive(.delegate(.engineReadinessUpdated(value)))
    }
    for value in readiness {
      await store.send(.engineReadinessUpdated(value)) { $0.snapshot.engineReadiness = value }
    }
    #expect(store.state.step == .tryIt)
  }

  @Test func `failed model setup can retry without keeping the old failure`() async {
    let readiness = [EngineReadiness.downloading(0), .compiling, .prewarming, .ready]
    var state = OnboardingFeature.State()
    state.isPresented = true
    state.snapshot = modelSnapshot(readiness: .failed("network unavailable"))
    state.failureMessage = "network unavailable"
    let store = TestStore(initialState: state) {
      OnboardingFeature()
    } withDependencies: {
      $0.asrEngine.installAndPrepare = {
        AsyncStream { continuation in
          for value in readiness {
            continuation.yield(value)
          }
          continuation.finish()
        }
      }
    }

    await store.send(.setupModel) { $0.failureMessage = nil }
    for value in readiness {
      await store.receive(.delegate(.engineReadinessUpdated(value)))
    }
    for value in readiness {
      await store.send(.engineReadinessUpdated(value)) { $0.snapshot.engineReadiness = value }
    }
    #expect(store.state.step == .tryIt)
  }

  @Test func `a real delivered dictation marks onboarding complete`() async {
    let completions = SynchronousCounter()
    var state = OnboardingFeature.State()
    state.isPresented = true
    state.snapshot = modelSnapshot(readiness: .ready)
    state.selectedStep = .tryIt
    let store = TestStore(initialState: state) {
      OnboardingFeature()
    } withDependencies: {
      $0.onboardingCompletion.markCompleted = { completions.increment() }
    }

    await store.send(.dictationDelivered("MiniWhisper is ready.")) {
      $0.tryItText = "MiniWhisper is ready."
      $0.completionIntent = .dictation
    }
    await store.receive(.completionMarked) {
      $0.snapshot.isCompleted = true
      $0.selectedStep = nil
      $0.completionIntent = nil
    }
    await store.receive(.delegate(.completed))
    #expect(completions.value == 1)
    #expect(store.state.step == .ready)

    await store.send(.finish) { $0.isPresented = false }
    await store.receive(.delegate(.dismissed))
  }

  @Test func `skip marks onboarding complete before dismissing`() async {
    let completions = SynchronousCounter()
    var state = OnboardingFeature.State()
    state.isPresented = true
    state.snapshot = modelSnapshot(readiness: .ready)
    let store = TestStore(initialState: state) {
      OnboardingFeature()
    } withDependencies: {
      $0.onboardingCompletion.markCompleted = { completions.increment() }
    }

    #expect(store.state.canSkip)
    await store.send(.skip) { $0.completionIntent = .skip }
    await store.receive(.completionMarked) {
      $0.snapshot.isCompleted = true
      $0.completionIntent = nil
    }
    await store.receive(.delegate(.completed))
    await store.receive(.finish) { $0.isPresented = false }
    await store.receive(.delegate(.dismissed))
    #expect(completions.value == 1)
  }

  @Test func `skip is unavailable outside the active try it step`() async {
    let completions = SynchronousCounter()
    var permissions = OnboardingFeature.State()
    permissions.isPresented = true
    var model = permissions
    model.snapshot = modelSnapshot(readiness: .modelMissing)
    var revisitingTryIt = model
    revisitingTryIt.selectedStep = .tryIt
    var ready = permissions
    ready.snapshot = modelSnapshot(readiness: .ready)
    ready.snapshot.isCompleted = true

    for state in [permissions, model, revisitingTryIt, ready] {
      let store = TestStore(initialState: state) {
        OnboardingFeature()
      } withDependencies: {
        $0.onboardingCompletion.markCompleted = { completions.increment() }
      }

      #expect(!store.state.canSkip)
      await store.send(.skip)
    }
    #expect(completions.value == 0)
  }

  // MARK: Private

  private func presentedPermissionsState() -> OnboardingFeature.State {
    var state = OnboardingFeature.State()
    state.isPresented = true
    return state
  }

  private func modelSnapshot(readiness: EngineReadiness) -> OnboardingSnapshot {
    OnboardingSnapshot(
      permissions: OnboardingPermissionStatuses(
        hasInputMonitoringPermission: true, microphoneStatus: .granted, hasPasteAccess: true,
      ),
      engineReadiness: readiness, hasModelDownloadConsent: true, isCompleted: false,
    )
  }
}

private let applicationLocation = URL(
  fileURLWithPath: "/Users/dev/.build/DerivedData/Debug/MiniWhisper.app",
)

private let grantedPermissionStatuses = OnboardingPermissionStatuses(
  hasInputMonitoringPermission: true, microphoneStatus: .granted, hasPasteAccess: true,
)

private func observation(
  _ statuses: OnboardingPermissionStatuses,
) -> OnboardingPermissionObservation {
  OnboardingPermissionObservation(
    hasInputMonitoringPermission: statuses.hasInputMonitoringPermission,
    microphoneStatus: statuses.microphoneStatus, hasPasteAccess: statuses.hasPasteAccess,
  )
}

// MARK: - SynchronousCounter

private final class SynchronousCounter: @unchecked Sendable {
  // MARK: Internal

  var value: Int {
    lock.withLock { count }
  }

  func increment() {
    lock.withLock { count += 1 }
  }

  // MARK: Private

  private let lock = NSLock()
  private var count = 0
}

// MARK: - SynchronousStatuses

private final class SynchronousStatuses: @unchecked Sendable {
  // MARK: Internal

  var value: OnboardingPermissionStatuses {
    lock.withLock { statuses }
  }

  func withValue(_ mutate: (inout OnboardingPermissionStatuses) -> Void) {
    lock.withLock { mutate(&statuses) }
  }

  // MARK: Private

  private let lock = NSLock()
  private var statuses = OnboardingPermissionStatuses(
    hasInputMonitoringPermission: false, microphoneStatus: .undetermined, hasPasteAccess: false,
  )
}

// MARK: - SynchronousStrings

private final class SynchronousStrings: @unchecked Sendable {
  // MARK: Internal

  var values: [String] {
    lock.withLock { storage }
  }

  func append(_ value: String) {
    lock.withLock { storage.append(value) }
  }

  // MARK: Private

  private let lock = NSLock()
  private var storage: [String] = []
}

// MARK: - SynchronousValues

private final class SynchronousValues: @unchecked Sendable {
  // MARK: Internal

  var values: [URL] {
    lock.withLock { storage }
  }

  func append(_ url: URL) {
    lock.withLock { storage.append(url) }
  }

  // MARK: Private

  private let lock = NSLock()
  private var storage: [URL] = []
}
