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

    await store.send(.bindingTapped(0)) { $0.target = .existing(0) }
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
      $0.$settings.withLock { $0.hotkeys = [replacement] }
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
    let store = TestStore(initialState: makeState(hotkeys: [.rightOption, extra])) {
      HotkeyBindingsFeature()
    }

    await store.send(.primaryBindingTapped) { $0.target = .existing(0) }
    await store.receive(.delegate(.recordingStarted))
    await store.send(.recorderEvent(.committed(replacement))) {
      $0.$settings.withLock { $0.hotkeys = [replacement, extra] }
      $0.target = nil
    }
    await store.receive(.delegate(.recordingStopped))
    #expect(store.state.hotkeys == [replacement, extra])
  }

  @Test func `A primary recording appends when there is no binding to replace`() async throws {
    let recorded = try Hotkey(keyCode: 0, modifiers: [.leftCommand])
    let store = TestStore(initialState: makeState(hotkeys: [])) { HotkeyBindingsFeature() }

    await store.send(.primaryBindingTapped) { $0.target = .new }
    await store.receive(.delegate(.recordingStarted))
    await store.send(.recorderEvent(.committed(recorded))) {
      $0.$settings.withLock { $0.hotkeys = [recorded] }
      $0.target = nil
    }
    await store.receive(.delegate(.recordingStopped))
  }

  @Test func `pressing the primary binding again mid-recording does not restart the recorder`(
  ) async {
    let store = TestStore(initialState: makeState()) { HotkeyBindingsFeature() }

    await store.send(.primaryBindingTapped) { $0.target = .existing(0) }
    await store.receive(.delegate(.recordingStarted))
    await store.send(.primaryBindingTapped)
  }

  @Test func `add and remove mutate the ordered bindings`() async throws {
    let added = try Hotkey(keyCode: 0, modifiers: [.leftCommand])
    let store = TestStore(initialState: makeState()) { HotkeyBindingsFeature() }

    await store.send(.addTapped) { $0.target = .new }
    await store.receive(.delegate(.recordingStarted))
    await store.send(.recorderEvent(.committed(added))) {
      $0.$settings.withLock { $0.hotkeys.append(added) }
      $0.target = nil
    }
    await store.receive(.delegate(.recordingStopped))
    await store.send(.removeTapped(0)) {
      $0.$settings.withLock { _ = $0.hotkeys.remove(at: 0) }
    }
    await store.receive(.delegate(.bindingsChanged))
    #expect(store.state.hotkeys == [added])
  }

  @Test func `A chord already bound anywhere commits as A silent no-op`() async throws {
    let extra = try Hotkey(keyCode: 15, modifiers: [.rightControl])
    let store = TestStore(initialState: makeState(hotkeys: [.rightOption, extra])) {
      HotkeyBindingsFeature()
    }

    // The binding it is already on…
    await store.send(.bindingTapped(0)) { $0.target = .existing(0) }
    await store.receive(.delegate(.recordingStarted))
    await store.send(.recorderEvent(.committed(.rightOption))) { $0.target = nil }
    await store.receive(.delegate(.recordingStopped))

    // …a sibling's binding…
    await store.send(.bindingTapped(0)) { $0.target = .existing(0) }
    await store.receive(.delegate(.recordingStarted))
    await store.send(.recorderEvent(.committed(extra))) { $0.target = nil }
    await store.receive(.delegate(.recordingStopped))

    // …and a new binding that duplicates an old one.
    await store.send(.addTapped) { $0.target = .new }
    await store.receive(.delegate(.recordingStarted))
    await store.send(.recorderEvent(.committed(.rightOption))) { $0.target = nil }
    await store.receive(.delegate(.recordingStopped))

    #expect(store.state.hotkeys == [.rightOption, extra])
  }

  @Test func `A missing replacement target drops the commit safely`() async throws {
    var state = makeState()
    state.target = .existing(7)
    let replacement = try Hotkey(keyCode: 15, modifiers: [.rightControl])
    let store = TestStore(initialState: state) { HotkeyBindingsFeature() }

    await store.send(.recorderEvent(.committed(replacement))) { $0.target = nil }
    await store.receive(.delegate(.recordingStopped))
    #expect(store.state.hotkeys == [.rightOption])
  }

  @Test func `escape cancellation preserves bindings`() async {
    let store = TestStore(initialState: makeState()) { HotkeyBindingsFeature() }

    await store.send(.bindingTapped(0)) { $0.target = .existing(0) }
    await store.receive(.delegate(.recordingStarted))
    await store.send(.cancelRecording) { $0.target = nil }
    await store.receive(.delegate(.recordingStopped))
    #expect(store.state.hotkeys == [.rightOption])
  }

  @Test func `invalid chords show why and remain recording`() async {
    let store = TestStore(initialState: makeState()) { HotkeyBindingsFeature() }

    await store.send(.addTapped) { $0.target = .new }
    await store.receive(.delegate(.recordingStarted))
    await store.send(.recorderEvent(.validationFailed(.multipleKeys))) {
      $0.validationMessage = "Use at most one non-modifier key."
    }
    #expect(store.state.target == .new)
  }

  // MARK: Private

  private func makeState(hotkeys: [Hotkey] = [.rightOption]) -> HotkeyBindingsFeature.State {
    var settings = MiniWhisperSettings.defaults
    settings.hotkeys = hotkeys
    return HotkeyBindingsFeature.State(settings: Shared(value: settings))
  }
}
