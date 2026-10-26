import AppSettings
import ASREngine
import AudioCapture
import ComposableArchitecture
import Foundation
import HotkeyListener
@testable import MiniWhisper
import ModelLibrary
import Testing
import TranscriptCleanup

// MARK: - OnboardingStepDerivationTests

struct OnboardingStepDerivationTests {
  @Test func `every permission must land before setup leaves the permissions step`() {
    var snapshot = OnboardingSnapshot(
      permissions: OnboardingPermissionStatuses(
        microphoneStatus: .undetermined, hasAccessibilityPermission: false,
      ),
      hasModelDownloadConsent: false, isCompleted: false,
    )
    var readiness = EngineReadiness.modelMissing
    #expect(
      OnboardingStep.derive(
        from: snapshot, isMissingKeys: false, isSetUp: readiness == .ready,
        hasCompletedShortcut: false,
      ) == .permissions,
    )

    snapshot.permissions.microphoneStatus = .granted
    #expect(
      OnboardingStep.derive(
        from: snapshot, isMissingKeys: false, isSetUp: readiness == .ready,
        hasCompletedShortcut: false,
      ) == .permissions,
    )

    snapshot.permissions.hasAccessibilityPermission = true
    #expect(
      OnboardingStep.derive(
        from: snapshot, isMissingKeys: false, isSetUp: readiness == .ready,
        hasCompletedShortcut: false,
      ) == .shortcut,
    )
    #expect(
      OnboardingStep.derive(
        from: snapshot, isMissingKeys: false, isSetUp: readiness == .ready,
        hasCompletedShortcut: true,
      ) == .model,
    )

    readiness = .ready
    #expect(
      OnboardingStep.derive(
        from: snapshot, isMissingKeys: false, isSetUp: readiness == .ready,
        hasCompletedShortcut: true,
      ) == .tryIt,
    )

    // A profile's missing key comes first: nothing after it can be finished without it.
    #expect(
      OnboardingStep.derive(
        from: snapshot, isMissingKeys: true, isSetUp: true, hasCompletedShortcut: true,
      ) == .keys,
    )

    snapshot.isCompleted = true
    #expect(
      OnboardingStep.derive(
        from: snapshot, isMissingKeys: false, isSetUp: readiness == .ready,
        hasCompletedShortcut: true,
      ) == .ready,
    )
  }

  @Test func `only the first ungranted permission owns the action`() {
    var state = OnboardingFeature.State()
    #expect(state.activePermission == .microphone)
    #expect(state.canRequest(.microphone))
    #expect(!state.canRequest(.accessibility))

    state.snapshot.permissions.microphoneStatus = .granted
    #expect(state.activePermission == .accessibility)
    #expect(state.canRequest(.accessibility))

    state.snapshot.permissions.hasAccessibilityPermission = true
    #expect(state.activePermission == nil)
  }

  @Test(arguments: [MicPermissionStatus.denied, .restricted, .undetermined, .unknown])
  func `every non granted microphone state stops at permissions`(_ status: MicPermissionStatus) {
    let snapshot = OnboardingSnapshot(
      permissions: OnboardingPermissionStatuses(
        microphoneStatus: status, hasAccessibilityPermission: true,
      ),
      hasModelDownloadConsent: true, isCompleted: true,
    )

    #expect(
      OnboardingStep.derive(
        from: snapshot, isMissingKeys: false, isSetUp: true, hasCompletedShortcut: true,
      ) == .permissions,
    )
    #expect(!snapshot.permissions.isGranted(.microphone))
  }
}

// MARK: - OnboardingFeatureTests

@MainActor struct OnboardingFeatureTests {
  // MARK: Internal

  @Test func `untouched first run waits for download consent`() async {
    let snapshot = OnboardingSnapshot(
      permissions: OnboardingPermissionStatuses(
        microphoneStatus: .undetermined, hasAccessibilityPermission: false,
      ),
      hasModelDownloadConsent: false, isCompleted: false,
    )
    let store = TestStore(initialState: OnboardingFeature.State()) {
      OnboardingFeature()
    } withDependencies: {
      $0.continuousClock = TestClock()
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.present(snapshot)) {
      $0.isPresented = true
      $0.snapshot = snapshot
      $0.isShowingWelcome = true
    }

    await store.send(.downloadModel) { $0.isRecordingModelDownloadConsent = true }
    await store.receive(.delegate(.setupModelRequested))
    await store.send(.modelDownloadConsented) {
      $0.snapshot.hasModelDownloadConsent = true
      $0.isShowingWelcome = false
      $0.isRecordingModelDownloadConsent = false
    }

    await store.send(.permissionStatusesObserved(grantedPermissionStatuses))
    await store.finish()
  }

  @Test func `consented relaunch skips welcome and resumes model setup`() async {
    let snapshot = OnboardingSnapshot(
      permissions: OnboardingPermissionStatuses(
        microphoneStatus: .undetermined, hasAccessibilityPermission: false,
      ),
      hasModelDownloadConsent: true, isCompleted: false,
    )
    let store = TestStore(initialState: OnboardingFeature.State()) {
      OnboardingFeature()
    } withDependencies: {
      $0.continuousClock = TestClock()
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.present(snapshot)) {
      $0.isPresented = true
      $0.snapshot = snapshot
    }
    #expect(!store.state.isShowingWelcome)
    await store.receive(.delegate(.setupModelRequested))
    await store.send(.permissionStatusesObserved(grantedPermissionStatuses))
    await store.finish()
  }

  @Test func `polling carries every visible grant to the model step`() async {
    let clock = TestClock()
    let statuses = SynchronousStatuses()
    let store = TestStore(initialState: OnboardingFeature.State()) {
      OnboardingFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.microphonePermission.status = { statuses.value.microphoneStatus }
      $0.accessibilityPermission.hasPermission = { statuses.value.hasAccessibilityPermission }
      $0.asrEngine.installAndPrepare = { _ in AsyncStream { $0.finish() } }
      $0.keychain.read = { _ in "sk-ant-test" }
    }

    let initialSnapshot = OnboardingSnapshot(
      permissions: OnboardingPermissionStatuses(
        microphoneStatus: .undetermined, hasAccessibilityPermission: false,
      ),
      hasModelDownloadConsent: true, isCompleted: false,
    )
    await store.send(.present(initialSnapshot)) {
      $0.isPresented = true
      $0.snapshot = initialSnapshot
      $0.storedKeys = [CredentialSlot(profile: .haiku, provider: .anthropic)]
    }
    await store.receive(.delegate(.setupModelRequested))

    statuses.withValue { $0.microphoneStatus = .granted }
    await clock.advance(by: .seconds(1))
    await store.receive(.refreshPermissionStatuses)
    await store.receive(.permissionStatusesObserved(statuses.value)) {
      $0.snapshot.permissions.microphoneStatus = .granted
    }
    await store.receive(.delegate(.permissionsUpdated(statuses.value)))
    #expect(store.state.step == .permissions)

    statuses.withValue { $0.hasAccessibilityPermission = true }
    await clock.advance(by: .seconds(1))
    await store.receive(.refreshPermissionStatuses)
    await store.receive(.permissionStatusesObserved(statuses.value)) {
      $0.snapshot.permissions.hasAccessibilityPermission = true
    }
    await store.receive(.delegate(.permissionsUpdated(statuses.value)))
    #expect(store.state.step == .shortcut)
  }

  @Test func `an accessibility prompt suspends checks and cannot be requested twice`() async {
    let clock = TestClock()
    let probes = SynchronousCounter()
    let requests = SynchronousCounter()
    var state = presentedPermissionsState()
    state.snapshot.permissions.microphoneStatus = .granted
    let store = TestStore(initialState: state) {
      OnboardingFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.microphonePermission.status = { .granted }
      $0.accessibilityPermission.hasPermission = {
        probes.increment()
        return false
      }
      $0.accessibilityPermission.requestPermission = {
        requests.increment()
        return false
      }
    }

    await store.send(.requestPermission(.accessibility)) {
      $0.requestingPermission = .accessibility
      $0.pendingSystemPermissionPrompt = .accessibility
      $0.requestedPermissions = [.accessibility]
    }
    await store.receive(.accessibilityPermissionRequested(false)) { $0.requestingPermission = nil }
    await store.send(.requestPermission(.accessibility))
    await store.send(.refreshPermissionStatuses)
    #expect(requests.value == 1)
    #expect(probes.value == 0)

    await store.send(.applicationBecameActive) { $0.pendingSystemPermissionPrompt = nil }
    await store.receive(
      .permissionStatusesObserved(
        OnboardingPermissionStatuses(
          microphoneStatus: .granted, hasAccessibilityPermission: false,
        ),
      ),
    )
    #expect(probes.value == 1)

    await store.send(.permissionStatusesObserved(grantedPermissionStatuses)) {
      $0.snapshot.permissions = grantedPermissionStatuses
    }
    await store.receive(.delegate(.permissionsUpdated(grantedPermissionStatuses)))
  }

  @Test func `an unfulfilled accessibility request pivots to system settings`() async {
    let opened = SynchronousValues()
    var state = presentedPermissionsState()
    state.snapshot.permissions.microphoneStatus = .granted
    let store = TestStore(initialState: state) {
      OnboardingFeature()
    } withDependencies: {
      $0.continuousClock = TestClock()
      $0.microphonePermission.status = { .granted }
      $0.accessibilityPermission.hasPermission = { false }
      $0.accessibilityPermission.requestPermission = { false }
      $0.workspace.open = { url in opened.append(url) }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.requestPermission(.accessibility)) {
      $0.requestingPermission = .accessibility
      $0.pendingSystemPermissionPrompt = .accessibility
      $0.requestedPermissions = [.accessibility]
    }
    await store.receive(.accessibilityPermissionRequested(false)) { $0.requestingPermission = nil }
    #expect(store.state.needsSystemSettings(for: .accessibility))

    await store.send(.openSystemSettings(.accessibility))
    await store.send(.permissionStatusesObserved(grantedPermissionStatuses))
    await store.finish()
    #expect(opened.values == [SystemSettingsPane.accessibility])
  }

  @Test func `an accessibility grant uses the request endpoint`() async {
    var state = presentedPermissionsState()
    state.snapshot.permissions.microphoneStatus = .granted
    let store = TestStore(initialState: state) {
      OnboardingFeature()
    } withDependencies: {
      $0.continuousClock = TestClock()
      $0.accessibilityPermission.requestPermission = { true }
    }
    store.exhaustivity = .off(showSkippedAssertions: false)

    await store.send(.requestPermission(.accessibility)) {
      $0.requestingPermission = .accessibility
      $0.pendingSystemPermissionPrompt = .accessibility
      $0.requestedPermissions = [.accessibility]
    }
    await store.receive(.accessibilityPermissionRequested(true)) {
      $0.requestingPermission = nil
      $0.pendingSystemPermissionPrompt = nil
      $0.snapshot.permissions.hasAccessibilityPermission = true
    }
    await store.receive(.delegate(.permissionsUpdated(store.state.snapshot.permissions)))
    await store.send(.permissionStatusesObserved(grantedPermissionStatuses))
    await store.finish()
  }

  @Test func `an already queued observation cannot mutate A waiting prompt`() async {
    var state = presentedPermissionsState()
    state.requestingPermission = .microphone
    state.pendingSystemPermissionPrompt = .microphone
    state.requestedPermissions = [.microphone]
    let store = TestStore(initialState: state) { OnboardingFeature() }

    await store.send(
      .permissionStatusesObserved(
        OnboardingPermissionStatuses(microphoneStatus: .denied, hasAccessibilityPermission: false),
      ),
    )
    #expect(store.state.requestingPermission == .microphone)
    #expect(store.state.snapshot.permissions.microphoneStatus == .undetermined)
  }

  @Test func `sidebar navigation overrides the view without changing truth`() async {
    let clock = TestClock()
    let snapshot = modelSnapshot()
    var state = OnboardingFeature.State()
    state.isPresented = true
    state.snapshot = snapshot
    state.hasCompletedShortcut = true
    let store = TestStore(initialState: state) {
      OnboardingFeature()
    } withDependencies: {
      $0.continuousClock = clock
      $0.microphonePermission.status = { .granted }
      $0.accessibilityPermission.hasPermission = { true }
    }

    await store.send(.navigate(.tryIt)) { $0.selectedStep = .tryIt }
    #expect(store.state.step == .model)
    #expect(store.state.visibleStep == .tryIt)

    await store.send(.navigate(.permissions)) { $0.selectedStep = .permissions }
    await store.receive(.permissionStatusesObserved(snapshot.permissions))
    #expect(store.state.isRevisitingPermissions)

    await store.send(.navigate(.model)) { $0.selectedStep = .model }
    await store.finish()
  }

  @Test func `a granted request flips the row immediately`() async {
    let state = presentedPermissionsState()
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
    await store.send(.permissionStatusesObserved(grantedPermissionStatuses)) {
      $0.snapshot.permissions = grantedPermissionStatuses
    }
    await store.receive(.delegate(.permissionsUpdated(grantedPermissionStatuses)))
  }

  @Test func `shortcut continue advances to the model step`() async {
    var state = OnboardingFeature.State()
    state.isPresented = true
    state.snapshot = modelSnapshot()
    let store = TestStore(initialState: state) { OnboardingFeature() }

    #expect(store.state.step == .shortcut)
    await store.send(.shortcutContinueTapped) {
      $0.hasCompletedShortcut = true
    }
    #expect(store.state.step == .model)
    #expect(store.state.visibleStep == .model)
  }

  @Test func `shortcut continue skips a model that became ready in the background`() async {
    var state = shortcutState()
    state.$health.withLock { $0.engineReadiness = .ready }
    let store = TestStore(initialState: state) { OnboardingFeature() }

    #expect(store.state.visibleStep == .shortcut)
    await store.send(.shortcutContinueTapped) {
      $0.hasCompletedShortcut = true
    }
    #expect(store.state.step == .tryIt)
    #expect(store.state.visibleStep == .tryIt)
  }

  @Test func `a revisited ready model continues to the derived next step`() async {
    var state = shortcutState()
    state.hasCompletedShortcut = true
    state.selectedStep = .model
    state.$health.withLock { $0.engineReadiness = .ready }
    let store = TestStore(initialState: state) { OnboardingFeature() }

    #expect(store.state.canContinueFromModel)
    await store.send(.modelContinueTapped) {
      $0.selectedStep = nil
    }
    #expect(store.state.visibleStep == .tryIt)
  }

  @Test func `the step is frozen while A recording is in flight`() async {
    var state = shortcutState()
    state.shortcutBindings.target = .existing(0)
    let store = TestStore(initialState: state) { OnboardingFeature() }

    await store.send(.shortcutContinueTapped)
    #expect(!store.state.hasCompletedShortcut)
    #expect(store.state.visibleStep == .shortcut)

    await store.send(.navigate(.permissions))
    #expect(store.state.visibleStep == .shortcut)
  }

  @Test func `the hero keycap records into the primary binding and keeps the rest`() async throws {
    let extra = try Hotkey(keyCode: 15, modifiers: [.rightControl])
    let replacement = try Hotkey(keyCode: 0, modifiers: [.leftCommand])
    let store = TestStore(initialState: shortcutState(hotkeys: [.testRightOption, extra])) {
      OnboardingFeature()
    }

    await store.send(.shortcutBindings(.primaryBindingTapped)) {
      $0.shortcutBindings.$recordingCommand.withLock { $0 = .activate }
      $0.shortcutBindings.target = .existing(0)
    }
    await store.receive(.shortcutBindings(.delegate(.recordingStarted)))
    await store.send(.shortcutBindings(.recorderEvent(.committed(replacement)))) {
      $0.shortcutBindings.$settings.withLock {
        $0.bindings.set([replacement, extra], for: .activate)
      }
      $0.shortcutBindings.$recordingCommand.withLock { $0 = nil }
      $0.shortcutBindings.target = nil
    }
    await store.receive(.shortcutBindings(.delegate(.recordingStopped)))
    #expect(store.state.hotkeys == [replacement, extra])
  }

  @Test func `escape keeps whatever was last committed`() async throws {
    let replacement = try Hotkey(keyCode: 0, modifiers: [.leftCommand])
    let store = TestStore(initialState: shortcutState()) { OnboardingFeature() }

    await store.send(.shortcutBindings(.primaryBindingTapped)) {
      $0.shortcutBindings.$recordingCommand.withLock { $0 = .activate }
      $0.shortcutBindings.target = .existing(0)
    }
    await store.receive(.shortcutBindings(.delegate(.recordingStarted)))
    await store.send(.shortcutBindings(.recorderEvent(.committed(replacement)))) {
      $0.shortcutBindings.$settings.withLock {
        $0.bindings.set([replacement], for: .activate)
      }
      $0.shortcutBindings.$recordingCommand.withLock { $0 = nil }
      $0.shortcutBindings.target = nil
    }
    await store.receive(.shortcutBindings(.delegate(.recordingStopped)))

    await store.send(.shortcutBindings(.primaryBindingTapped)) {
      $0.shortcutBindings.$recordingCommand.withLock { $0 = .activate }
      $0.shortcutBindings.target = .existing(0)
    }
    await store.receive(.shortcutBindings(.delegate(.recordingStarted)))
    await store.send(.shortcutBindings(.recorderEvent(.cancelled))) {
      $0.shortcutBindings.$recordingCommand.withLock { $0 = nil }
      $0.shortcutBindings.target = nil
    }
    await store.receive(.shortcutBindings(.delegate(.recordingStopped)))
    #expect(store.state.hotkeys == [replacement])
  }

  @Test func `model setup is delegated upward and observes shared progress`() async {
    let health = Shared(value: AppHealth())
    var state = OnboardingFeature.State(health: health)
    state.isPresented = true
    state.snapshot = modelSnapshot()
    state.hasCompletedShortcut = true
    let store = TestStore(initialState: state) { OnboardingFeature() }

    await store.send(.setupModel)
    await store.receive(.delegate(.setupModelRequested))
    for readiness in [EngineReadiness.downloading(0.4), .compiling, .prewarming, .ready] {
      health.withLock { $0.engineReadiness = readiness }
      #expect(store.state.engineReadiness == readiness)
    }
    #expect(store.state.step == .tryIt)
  }

  @Test func `failed model setup can retry without keeping the old failure`() async {
    var state = OnboardingFeature.State()
    state.isPresented = true
    state.snapshot = modelSnapshot()
    state.$health.withLock { $0.engineReadiness = .failed("network unavailable") }
    state.hasCompletedShortcut = true
    state.failureMessage = "network unavailable"
    let store = TestStore(initialState: state) { OnboardingFeature() }

    await store.send(.setupModel) { $0.failureMessage = nil }
    await store.receive(.delegate(.setupModelRequested))
  }

  @Test func `a setup already running is not asked for twice`() async {
    var state = OnboardingFeature.State()
    state.isPresented = true
    state.snapshot = modelSnapshot()
    state.$health.withLock { $0.engineReadiness = .downloading(0.5) }
    state.hasCompletedShortcut = true
    let store = TestStore(initialState: state) { OnboardingFeature() }

    await store.send(.setupModel)
  }

  @Test func `a real delivered dictation marks onboarding complete`() async {
    let completions = SynchronousCounter()
    var state = OnboardingFeature.State()
    state.isPresented = true
    state.snapshot = modelSnapshot()
    state.$health.withLock { $0.engineReadiness = .ready }
    state.hasCompletedShortcut = true
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
    state.snapshot = modelSnapshot()
    state.$health.withLock { $0.engineReadiness = .ready }
    state.hasCompletedShortcut = true
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

  @Test func `skip is unavailable on every page but the last`() async {
    let completions = SynchronousCounter()
    var permissions = OnboardingFeature.State()
    permissions.isPresented = true
    var model = OnboardingFeature.State()
    model.isPresented = true
    model.snapshot = modelSnapshot()
    model.hasCompletedShortcut = true
    var ready = OnboardingFeature.State()
    ready.isPresented = true
    ready.snapshot = modelSnapshot()
    ready.$health.withLock { $0.engineReadiness = .ready }
    ready.hasCompletedShortcut = true
    ready.snapshot.isCompleted = true

    for state in [permissions, model, ready] {
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

  @Test func `the last page can be skipped with the flow unfinished`() async {
    let completions = SynchronousCounter()
    var state = OnboardingFeature.State()
    state.isPresented = true
    state.snapshot = modelSnapshot()
    state.hasCompletedShortcut = true
    state.selectedStep = .tryIt
    let store = TestStore(initialState: state) {
      OnboardingFeature()
    } withDependencies: {
      $0.onboardingCompletion.markCompleted = { completions.increment() }
    }

    #expect(store.state.step == .model)
    #expect(store.state.canSkip)

    await store.send(.skip) { $0.completionIntent = .skip }
    await store.receive(.completionMarked) {
      $0.snapshot.isCompleted = true
      $0.selectedStep = nil
      $0.completionIntent = nil
    }
    await store.receive(.delegate(.completed))
    await store.receive(.finish) { $0.isPresented = false }
    await store.receive(.delegate(.dismissed))
    #expect(completions.value == 1)
  }

  // MARK: Private

  private func presentedPermissionsState() -> OnboardingFeature.State {
    var state = OnboardingFeature.State()
    state.isPresented = true
    return state
  }

  private func shortcutState(hotkeys: [Hotkey] = [.testRightOption]) -> OnboardingFeature.State {
    var settings = MiniWhisperSettings.defaults
    settings.bindings.set(hotkeys, for: .activate)
    var state = OnboardingFeature.State(settings: Shared(value: settings))
    state.isPresented = true
    state.snapshot = modelSnapshot()
    return state
  }

  private func modelSnapshot() -> OnboardingSnapshot {
    OnboardingSnapshot(
      permissions: OnboardingPermissionStatuses(
        microphoneStatus: .granted, hasAccessibilityPermission: true,
      ),
      hasModelDownloadConsent: true, isCompleted: false,
    )
  }
}

// MARK: - OnboardingProfileTests

@MainActor struct OnboardingProfileTests {
  // MARK: Internal

  /// What the button downloads is the chosen profile's models, minus the megabyte gate that rides
  /// along with anything; a profile with nothing large to fetch just starts.
  @Test(arguments: [
    (ProfileID.haiku, "Download Parakeet TDT v2"),
    (.offline, "Download Parakeet TDT v2 and S1-mini"),
    (.accurate, "Get Started"),
    (.custom, "Download Parakeet TDT v2"),
  ])
  func `the welcome button names what the chosen profile downloads`(
    _ id: ProfileID, title: String,
  ) {
    var state = welcomeState()
    state.$settings.withLock { $0.profiles.active = id }
    #expect(state.welcomeActionTitle == title)
  }

  @Test func `the footnote sizes the download and names the keys that come next`() {
    var state = welcomeState()
    state.storedKeys = [CredentialSlot(profile: .accurate, provider: .google)]
    state.$settings.withLock { $0.profiles.active = .accurate }
    #expect(state.welcomeFootnote == "You’ll add an ElevenLabs key next.")
    state.storedKeys = []
    #expect(state.welcomeFootnote == "You’ll add ElevenLabs and Google keys next.")

    state.$settings.withLock { $0.profiles.active = .offline }
    state.assets[.parakeet] = .installed(bytes: ModelAsset.parakeet.pinnedBytes)
    let size = ByteCountFormatter.string(
      fromByteCount: Int64(ModelAsset.s1Mini.pinnedBytes), countStyle: .file,
    )
    #expect(state.welcomeActionTitle == "Download S1-mini")
    #expect(state.welcomeFootnote == "\(size) downloads while you finish setup.")
  }

  /// Most accurate needs two keys, each in its own slot: a key pasted into the wrong one would be
  /// sent to the wrong company.
  @Test func `every missing key must be typed, and each lands in its own slot`() async {
    let stored = TestBox<[CredentialSlot: String]>([:])
    var state = welcomeState()
    state.isShowingWelcome = false
    state.snapshot.hasModelDownloadConsent = true
    state.$settings.withLock { $0.profiles.active = .accurate }
    state.storedKeys = []
    let verified = TestBox<(CleanupConfiguration, String?)?>(nil)
    let engineChecked = TestBox<(SpeechEngine, String)?>(nil)
    let store = TestStore(initialState: state) {
      OnboardingFeature()
    } withDependencies: {
      $0.keychain.store = { key, slot in stored.value[slot] = key }
      $0.keychain.read = { stored.value[$0] }
      $0.asrEngine.verifyKey = { engine, key in
        #expect(stored.value.isEmpty, "Nothing is stored before the engine key is proven")
        engineChecked.value = (engine, key)
      }
      $0.cleanup.verify = { configuration, key in
        #expect(stored.value.isEmpty, "Nothing is stored before the cleanup key is proven")
        verified.value = (configuration, key)
        return .verified
      }
    }
    let elevenLabs = CredentialSlot(profile: .accurate, provider: .elevenlabs)
    let google = CredentialSlot(profile: .accurate, provider: .google)
    #expect(store.state.step == .keys)

    await store
      .send(.keyEdited(elevenLabs, " sk_eleven ")) { $0.keyDrafts[elevenLabs] = " sk_eleven " }
    #expect(!store.state.canContinueFromKeys)
    await store.send(.keysContinueTapped)
    #expect(stored.value.isEmpty)

    await store.send(.keyEdited(google, "AIzaGoogle")) { $0.keyDrafts[google] = "AIzaGoogle" }
    await store.send(.keysContinueTapped) { $0.isCheckingKeys = true }
    await store.receive(.keysVerified) {
      $0.isCheckingKeys = false
      $0.storedKeys = [elevenLabs, google]
      $0.keyDrafts = [:]
    }
    await store.receive(.delegate(.keysStored))

    #expect(verified.value?.0.endpoint.host() == "generativelanguage.googleapis.com")
    #expect(verified.value?.0.model == "gemini-3.8-flash")
    #expect(verified.value?.1 == "AIzaGoogle")
    #expect(engineChecked.value?.0 == .scribe)
    #expect(engineChecked.value?.1 == "sk_eleven")
    #expect(stored.value == [elevenLabs: "sk_eleven", google: "AIzaGoogle"])
    #expect(store.state.step == .permissions)
  }

  @Test func `a cleanup key the provider refuses is never stored`() async {
    var state = welcomeState()
    state.isShowingWelcome = false
    state.snapshot.hasModelDownloadConsent = true
    state.storedKeys = []
    let haiku = CredentialSlot(profile: .haiku, provider: .anthropic)
    let store = TestStore(initialState: state) {
      OnboardingFeature()
    } withDependencies: {
      $0.keychain.store = { _, _ in Issue.record("A refused key is never stored") }
      $0.cleanup.verify = { _, _ in .failed(.httpStatus(code: 401, message: nil)) }
    }

    await store.send(.keyEdited(haiku, "sk-ant-wrong")) { $0.keyDrafts[haiku] = "sk-ant-wrong" }
    await store.send(.keysContinueTapped) { $0.isCheckingKeys = true }
    await store.receive(.keysCheckFailed("Invalid Anthropic key.")) {
      $0.isCheckingKeys = false
      $0.failureMessage = "Invalid Anthropic key."
    }
    #expect(store.state.step == .keys)
    #expect(store.state.canContinueFromKeys)
  }

  @Test func `an engine key Scribe refuses stops the step before cleanup is asked`() async {
    var state = welcomeState()
    state.isShowingWelcome = false
    state.snapshot.hasModelDownloadConsent = true
    state.$settings.withLock { $0.profiles.active = .accurate }
    state.storedKeys = []
    let elevenLabs = CredentialSlot(profile: .accurate, provider: .elevenlabs)
    let google = CredentialSlot(profile: .accurate, provider: .google)
    let store = TestStore(initialState: state) {
      OnboardingFeature()
    } withDependencies: {
      $0.keychain.store = { _, _ in Issue.record("A refused key is never stored") }
      $0.asrEngine.verifyKey = { _, _ in throw ASREngineError.credentialRejected }
    }

    await store.send(.keyEdited(elevenLabs, "sk_wrong")) { $0.keyDrafts[elevenLabs] = "sk_wrong" }
    await store.send(.keyEdited(google, "AIzaGoogle")) { $0.keyDrafts[google] = "AIzaGoogle" }
    await store.send(.keysContinueTapped) { $0.isCheckingKeys = true }
    await store.receive(.keysCheckFailed("Invalid ElevenLabs key.")) {
      $0.isCheckingKeys = false
      $0.failureMessage = "Invalid ElevenLabs key."
    }
    #expect(store.state.step == .keys)
  }

  @Test func `the way past a factory key is Custom with no cleanup`() async {
    var state = welcomeState()
    state.isShowingWelcome = false
    state.storedKeys = []
    state.$settings.withLock { $0.profiles.custom.cleanupEnabled = true }
    let store = TestStore(initialState: state) {
      OnboardingFeature()
    } withDependencies: {
      $0.keychain.read = { _ in nil }
    }
    #expect(store.state.step == .keys)

    await store.send(.useCustomTapped) {
      $0.$settings.withLock {
        $0.profiles.active = .custom
        $0.profiles.custom.cleanupEnabled = false
      }
      $0.storedKeys = []
    }
    await store.receive(.delegate(.profileSelected))
    #expect(store.state.step == .permissions)
  }

  /// Skipping the key is allowed, not advised: the rail moves on, but Try It has nothing that
  /// can dictate, and Skip is the way out of it.
  @Test func `a skipped key moves the rail on and leaves nothing to try`() async {
    var state = welcomeState()
    state.isShowingWelcome = false
    state.snapshot = OnboardingSnapshot(
      permissions: grantedPermissionStatuses, hasModelDownloadConsent: true, isCompleted: false,
    )
    state.hasCompletedShortcut = true
    state.$health.withLock { $0.engineReadiness = .ready }
    state.storedKeys = []
    let store = TestStore(initialState: state) { OnboardingFeature() }
    #expect(store.state.step == .keys)

    await store.send(.keysSkipped) { $0.hasSkippedKeys = true }
    #expect(store.state.step == .tryIt)
    #expect(!store.state.canTryDictation)
    #expect(store.state.canSkip)
  }

  /// The choice belongs to the welcome page: once the download it chose has started, another
  /// card press would leave the rail describing a profile that is not downloading.
  @Test func `a profile is chosen only on the welcome page`() async {
    var state = welcomeState()
    let store = TestStore(initialState: state) {
      OnboardingFeature()
    } withDependencies: {
      $0.keychain.read = { _ in nil }
    }
    await store.send(.profileSelected(.offline)) {
      $0.$settings.withLock { $0.profiles.active = .offline }
      $0.storedKeys = []
    }
    await store.receive(.delegate(.profileSelected))

    state = store.state
    state.isShowingWelcome = false
    let later = TestStore(initialState: state) { OnboardingFeature() }
    await later.send(.profileSelected(.haiku))
  }

  /// Offline's cleanup model is part of its setup, so the engine being ready is not the end of the
  /// Speech Model step until S1-mini is on disk too.
  @Test func `offline waits on its cleanup model as well as its engine`() {
    var state = welcomeState()
    state.isShowingWelcome = false
    state.snapshot = OnboardingSnapshot(
      permissions: grantedPermissionStatuses, hasModelDownloadConsent: true, isCompleted: false,
    )
    state.hasCompletedShortcut = true
    state.$health.withLock { $0.engineReadiness = .ready }
    state.$settings.withLock { $0.profiles.active = .offline }
    state.assets = [.s1Mini: .downloading(0.5)]
    #expect(state.step == .model)
    #expect(!state.needsModelSetup)

    state.assets[.s1Mini] = .failed("offline")
    #expect(state.needsModelSetup)

    state.assets[.s1Mini] = .installed(bytes: 1)
    #expect(state.step == .tryIt)
  }

  // MARK: Private

  private func welcomeState() -> OnboardingFeature.State {
    var state = OnboardingFeature.State(settings: Shared(value: .defaults))
    state.isPresented = true
    state.isShowingWelcome = true
    return state
  }
}

private let grantedPermissionStatuses = OnboardingPermissionStatuses(
  microphoneStatus: .granted, hasAccessibilityPermission: true,
)

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
    microphoneStatus: .undetermined, hasAccessibilityPermission: false,
  )
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
