import AppSettings
import ComposableArchitecture
import HotkeyListener
@testable import MiniWhisper
import Testing

@MainActor struct HotkeyBindingsFeatureTests {
  // MARK: Internal

  @Test func `recording replaces a binding on commit`() async throws {
    let (events, continuation) = AsyncStream.makeStream(of: HotkeyRecorderEvent.self)
    let replacement = try Hotkey(keyCode: 15, modifiers: [.rightControl])
    let store = TestStore(initialState: makeState()) {
      HotkeyBindingsFeature()
    } withDependencies: {
      $0.hotkeyListener.record = { events }
    }

    await store.send(.bindingTapped(0)) {
      $0.$recordingCommand.withLock { $0 = .activate }
      $0.target = .existing(0)
    }
    await store.receive(.delegate(.recordingStarted))
    await store.send(.recorderReady)
    continuation.yield(
      .chordChanged(HotkeyRecordingChord(keyCodes: [15], modifiers: [.rightControl])),
    )
    await store.receive(
      .recorderEvent(
        .chordChanged(HotkeyRecordingChord(keyCodes: [15], modifiers: [.rightControl])),
      ),
    ) {
      $0.liveChord = HotkeyRecordingChord(keyCodes: [15], modifiers: [.rightControl])
    }
    continuation.yield(.committed(replacement))
    await store.receive(.recorderEvent(.committed(replacement))) {
      $0.$settings.withLock { $0.bindings.set([replacement], for: .activate) }
      $0.$recordingCommand.withLock { $0 = nil }
      $0.target = nil
      $0.liveChord = nil
    }
    await store.receive(.delegate(.recordingStopped))
    continuation.finish()
    await store.receive(.recorderFinished)
  }

  @Test func `the primary binding is the first one, and the only one A commit replaces`(
  ) async throws {
    let extra = try Hotkey(keyCode: 15, modifiers: [.rightControl])
    let replacement = try Hotkey(keyCode: 0, modifiers: [.leftCommand])
    let store = TestStore(initialState: makeState(hotkeys: [.testRightOption, extra])) {
      HotkeyBindingsFeature()
    }

    await store.send(.primaryBindingTapped) {
      $0.$recordingCommand.withLock { $0 = .activate }
      $0.target = .existing(0)
    }
    await store.receive(.delegate(.recordingStarted))
    await store.send(.recorderEvent(.committed(replacement))) {
      $0.$settings.withLock { $0.bindings.set([replacement, extra], for: .activate) }
      $0.$recordingCommand.withLock { $0 = nil }
      $0.target = nil
    }
    await store.receive(.delegate(.recordingStopped))
    #expect(store.state.hotkeys == [replacement, extra])
  }

  @Test func `A primary recording appends when there is no binding to replace`() async throws {
    let recorded = try Hotkey(keyCode: 0, modifiers: [.leftCommand])
    let store = TestStore(initialState: makeState(hotkeys: [])) { HotkeyBindingsFeature() }

    await store.send(.primaryBindingTapped) {
      $0.$recordingCommand.withLock { $0 = .activate }
      $0.target = .new
    }
    await store.receive(.delegate(.recordingStarted))
    await store.send(.recorderEvent(.committed(recorded))) {
      $0.$settings.withLock { $0.bindings.set([recorded], for: .activate) }
      $0.$recordingCommand.withLock { $0 = nil }
      $0.target = nil
    }
    await store.receive(.delegate(.recordingStopped))
  }

  @Test func `pressing the primary binding again mid-recording does not restart the recorder`(
  ) async {
    let store = TestStore(initialState: makeState()) { HotkeyBindingsFeature() }

    await store.send(.primaryBindingTapped) {
      $0.$recordingCommand.withLock { $0 = .activate }
      $0.target = .existing(0)
    }
    await store.receive(.delegate(.recordingStarted))
    await store.send(.primaryBindingTapped)
  }

  @Test func `add and remove mutate the ordered bindings`() async throws {
    let added = try Hotkey(keyCode: 0, modifiers: [.leftCommand])
    let store = TestStore(initialState: makeState()) { HotkeyBindingsFeature() }

    await store.send(.addTapped) {
      $0.$recordingCommand.withLock { $0 = .activate }
      $0.target = .new
    }
    await store.receive(.delegate(.recordingStarted))
    await store.send(.recorderEvent(.committed(added))) {
      $0.$settings.withLock { _ = $0.bindings.append(added, for: .activate) }
      $0.$recordingCommand.withLock { $0 = nil }
      $0.target = nil
    }
    await store.receive(.delegate(.recordingStopped))
    await store.send(.removeTapped(0)) {
      $0.$settings.withLock { _ = $0.bindings.remove(at: 0, for: .activate) }
    }
    await store.receive(.delegate(.bindingsChanged))
    #expect(store.state.hotkeys == [added])
  }

  @Test func `A chord already bound anywhere commits as A silent no-op`() async throws {
    let extra = try Hotkey(keyCode: 15, modifiers: [.rightControl])
    let store = TestStore(initialState: makeState(hotkeys: [.testRightOption, extra])) {
      HotkeyBindingsFeature()
    }

    // The binding it is already on…
    await store.send(.bindingTapped(0)) {
      $0.$recordingCommand.withLock { $0 = .activate }
      $0.target = .existing(0)
    }
    await store.receive(.delegate(.recordingStarted))
    await store.send(.recorderEvent(.committed(.testRightOption))) {
      $0.$recordingCommand.withLock { $0 = nil }
      $0.target = nil
    }
    await store.receive(.delegate(.recordingStopped))

    // …a sibling's binding…
    await store.send(.bindingTapped(0)) {
      $0.$recordingCommand.withLock { $0 = .activate }
      $0.target = .existing(0)
    }
    await store.receive(.delegate(.recordingStarted))
    await store.send(.recorderEvent(.committed(extra))) {
      $0.$recordingCommand.withLock { $0 = nil }
      $0.target = nil
    }
    await store.receive(.delegate(.recordingStopped))

    // …and a new binding that duplicates an old one.
    await store.send(.addTapped) {
      $0.$recordingCommand.withLock { $0 = .activate }
      $0.target = .new
    }
    await store.receive(.delegate(.recordingStarted))
    await store.send(.recorderEvent(.committed(.testRightOption))) {
      $0.$recordingCommand.withLock { $0 = nil }
      $0.target = nil
    }
    await store.receive(.delegate(.recordingStopped))

    #expect(store.state.hotkeys == [.testRightOption, extra])
  }

  @Test func `A missing replacement target drops the commit safely`() async throws {
    var state = makeState()
    state.target = .existing(7)
    let replacement = try Hotkey(keyCode: 15, modifiers: [.rightControl])
    let store = TestStore(initialState: state) { HotkeyBindingsFeature() }

    await store.send(.recorderEvent(.committed(replacement))) { $0.target = nil }
    await store.receive(.delegate(.recordingStopped))
    #expect(store.state.hotkeys == [.testRightOption])
  }

  @Test func `escape cancellation preserves bindings`() async {
    let store = TestStore(initialState: makeState()) { HotkeyBindingsFeature() }

    await store.send(.bindingTapped(0)) {
      $0.$recordingCommand.withLock { $0 = .activate }
      $0.target = .existing(0)
    }
    await store.receive(.delegate(.recordingStarted))
    await store.send(.cancelRecording) {
      $0.$recordingCommand.withLock { $0 = nil }
      $0.target = nil
    }
    await store.receive(.delegate(.recordingStopped))
    #expect(store.state.hotkeys == [.testRightOption])
  }

  @Test func `invalid chords show why and remain recording`() async {
    let store = TestStore(initialState: makeState()) { HotkeyBindingsFeature() }

    await store.send(.addTapped) {
      $0.$recordingCommand.withLock { $0 = .activate }
      $0.target = .new
    }
    await store.receive(.delegate(.recordingStarted))
    await store.send(.recorderEvent(.validationFailed(.multipleKeys))) {
      $0.validationMessage = "Use at most one non-modifier key."
    }
    #expect(store.state.target == .new)
  }

  @Test(arguments: HotkeyCommand.allCases)
  func `commits edit only the selected action`(
    _ command: HotkeyCommand,
  ) async throws {
    let replacement = try Hotkey(keyCode: 15, modifiers: [.rightControl])
    let original = command == .activate
      ? Hotkey.testRightOption : .testPasteLastTranscript
    var state = makeState(hotkeys: [original], command: command)
    state.target = .existing(0)
    let store = TestStore(initialState: state) { HotkeyBindingsFeature() }

    await store.send(.recorderEvent(.committed(replacement))) {
      $0.$settings.withLock { $0.bindings.set([replacement], for: command) }
      $0.$recordingCommand.withLock { $0 = nil }
      $0.target = nil
    }
    await store.receive(.delegate(.recordingStopped))

    #expect(store.state.hotkeys == [replacement])
    let otherCommand = HotkeyCommand.allCases.first { $0 != command }
    #expect(
      try store.state.settings.bindings.hotkeys(for: #require(otherCommand))
        == [command == .activate ? .testPasteLastTranscript : .testRightOption],
    )
  }

  @Test(arguments: HotkeyCommand.allCases)
  func `a chord owned by the other action is silently rejected`(
    _ command: HotkeyCommand,
  ) async {
    let original = command == .activate
      ? Hotkey.testRightOption : .testPasteLastTranscript
    let duplicate = command == .activate
      ? Hotkey.testPasteLastTranscript : .testRightOption
    var state = makeState(hotkeys: [original], command: command)
    state.target = .existing(0)
    let store = TestStore(initialState: state) { HotkeyBindingsFeature() }

    await store.send(.recorderEvent(.committed(duplicate))) {
      $0.$recordingCommand.withLock { $0 = nil }
      $0.target = nil
    }
    await store.receive(.delegate(.recordingStopped))
    #expect(store.state.hotkeys == [original])
    #expect(store.state.validationMessage == nil)
  }

  @Test func `paste last can remove its final binding`() async {
    let store = TestStore(
      initialState: makeState(
        hotkeys: [.testPasteLastTranscript], command: .pasteLastTranscript,
      ),
    ) { HotkeyBindingsFeature() }

    await store.send(.removeTapped(0)) {
      $0.$settings.withLock { $0.bindings.set([], for: .pasteLastTranscript) }
    }
    await store.receive(.delegate(.bindingsChanged))
    #expect(store.state.hotkeys.isEmpty)
  }

  // MARK: Private

  private func makeState(
    hotkeys: [Hotkey] = [.testRightOption],
    command: HotkeyCommand = .activate,
  ) -> HotkeyBindingsFeature.State {
    var settings = MiniWhisperSettings.defaults
    settings.bindings.set(hotkeys, for: command)
    return HotkeyBindingsFeature.State(
      settings: Shared(value: settings), command: command,
    )
  }
}
