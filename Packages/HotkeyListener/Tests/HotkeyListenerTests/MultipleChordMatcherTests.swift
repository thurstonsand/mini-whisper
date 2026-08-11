@testable import HotkeyListener
import Testing

struct MultipleChordMatcherTests {
  // MARK: Internal

  @Test func `either binding activates`() throws {
    let controlR = try Hotkey(keyCode: 15, modifiers: [.rightControl])
    var matcher = MultipleChordMatcher(hotkeys: [.testRightOption, controlR])

    let option = matcher.receive(
      transition(.modifier(.rightOption), .down, [.modifier(.rightOption)]),
    )
    #expect(option.input == .activation(at: .zero))
    _ = matcher.receive(transition(.modifier(.rightOption), .up, []))

    _ = matcher.receive(
      transition(.modifier(.rightControl), .down, [.modifier(.rightControl)]),
    )
    let keyed = matcher.receive(
      transition(
        .keyCode(15), .down, [.modifier(.rightControl), .keyCode(15)],
        time: .milliseconds(10),
      ),
    )
    #expect(keyed.input == .activation(at: .milliseconds(10)))
  }

  @Test func `another binding is ignored until the active binding releases`() throws {
    let controlR = try Hotkey(keyCode: 15, modifiers: [.rightControl])
    var matcher = MultipleChordMatcher(hotkeys: [.testRightOption, controlR])
    _ = matcher.receive(
      transition(.modifier(.rightOption), .down, [.modifier(.rightOption)]),
    )

    let otherModifier = matcher.receive(
      transition(
        .modifier(.rightControl), .down,
        [.modifier(.rightOption), .modifier(.rightControl)], time: .milliseconds(10),
      ),
    )
    let otherKey = matcher.receive(
      transition(
        .keyCode(15), .down,
        [.modifier(.rightOption), .modifier(.rightControl), .keyCode(15)],
        time: .milliseconds(20),
      ),
    )
    #expect(otherModifier.input == nil)
    #expect(otherKey.input == nil)

    let release = matcher.receive(
      transition(
        .modifier(.rightOption), .up, [.modifier(.rightControl), .keyCode(15)],
        time: .milliseconds(30),
      ),
    )
    #expect(release.input == .release(at: .milliseconds(30)))
  }

  @Test func `duplicate bindings emit one activation per press`() {
    var matcher = MultipleChordMatcher(hotkeys: [.testRightOption, .testRightOption])
    var inputs: [GestureInput] = []

    for time in [Duration.zero, .milliseconds(100)] {
      if let input = matcher.receive(
        transition(
          .modifier(.rightOption), .down, [.modifier(.rightOption)], time: time,
        ),
      )
      .input {
        inputs.append(input)
      }
      if let input = matcher.receive(
        transition(
          .modifier(.rightOption), .up, [], time: time + .milliseconds(50),
        ),
      )
      .input {
        inputs.append(input)
      }
    }

    #expect(inputs == [
      .activation(at: .zero), .release(at: .milliseconds(50)),
      .activation(at: .milliseconds(100)), .release(at: .milliseconds(150)),
    ])
  }

  @Test func `action binding fires without entering the activation gesture`() throws {
    let paste = try Hotkey(keyCode: 9, modifiers: [.leftOption, .leftCommand])
    var matcher = MultipleChordMatcher(bindings: [
      HotkeyBinding(hotkey: .testRightOption, action: .activate),
      HotkeyBinding(hotkey: paste, action: .pasteLastTranscript),
    ])

    _ = matcher.receive(
      transition(.modifier(.leftOption), .down, [.modifier(.leftOption)]),
    )
    _ = matcher.receive(
      transition(
        .modifier(.leftCommand), .down,
        [.modifier(.leftOption), .modifier(.leftCommand)],
      ),
    )
    let completion = matcher.receive(
      transition(
        .keyCode(9), .down,
        [.modifier(.leftOption), .modifier(.leftCommand), .keyCode(9)],
      ),
    )
    let release = matcher.receive(
      transition(
        .keyCode(9), .up, [.modifier(.leftOption), .modifier(.leftCommand)],
      ),
    )

    #expect(completion.action == .pasteLastTranscript)
    #expect(completion.input == nil)
    #expect(completion.disposition == .suppress)
    #expect(release.action == nil)
    #expect(release.input == nil)
    #expect(release.disposition == .suppress)
  }

  @Test func `activation alternatives still route gestures beside an action binding`() {
    var matcher = MultipleChordMatcher(bindings: [
      HotkeyBinding(hotkey: .testRightOption, action: .activate),
      HotkeyBinding(hotkey: .testPasteLastTranscript, action: .pasteLastTranscript),
    ])

    let activation = matcher.receive(
      transition(.modifier(.rightOption), .down, [.modifier(.rightOption)]),
    )
    let release = matcher.receive(
      transition(.modifier(.rightOption), .up, []),
    )

    #expect(activation.input == .activation(at: .zero))
    #expect(activation.action == nil)
    #expect(release.input == .release(at: .zero))
    #expect(release.action == nil)
  }

  @Test func `building one alternative does not conflict with another`() throws {
    let controlR = try Hotkey(keyCode: 15, modifiers: [.rightControl])
    var matcher = MultipleChordMatcher(hotkeys: [.testRightOption, controlR])

    let partial = matcher.receive(
      transition(.modifier(.rightControl), .down, [.modifier(.rightControl)]),
    )
    #expect(partial.input == nil)
  }

  // MARK: Private

  private func transition(
    _ key: PhysicalKey, _ phase: KeyPhase, _ pressedAfter: Set<PhysicalKey>,
    time: Duration = .zero,
  ) -> KeyTransition {
    KeyTransition(key: key, phase: phase, pressedAfter: pressedAfter, time: time)
  }
}
