@testable import HotkeyListener
import Testing

// MARK: - MultipleChordMatcherTests

struct MultipleChordMatcherTests {
  // MARK: Internal

  @Test func `either binding activates`() throws {
    let controlR = try Hotkey(keyCode: 15, modifiers: [.rightControl])
    var matcher = gestureMatcher([.testRightOption, controlR])

    let option = matcher.receive(
      transition(.modifier(.rightOption), .down, [.modifier(.rightOption)]),
    )
    #expect(option.gestureInput == .activation(at: .zero))
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
    #expect(keyed.gestureInput == .activation(at: .milliseconds(10)))
  }

  @Test func `another binding is ignored until the active binding releases`() throws {
    let controlR = try Hotkey(keyCode: 15, modifiers: [.rightControl])
    var matcher = gestureMatcher([.testRightOption, controlR])
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
    #expect(otherModifier.output == nil)
    #expect(otherKey.output == nil)

    let release = matcher.receive(
      transition(
        .modifier(.rightOption), .up, [.modifier(.rightControl), .keyCode(15)],
        time: .milliseconds(30),
      ),
    )
    #expect(release.gestureInput == .release(at: .milliseconds(30)))
  }

  @Test func `duplicate bindings emit one activation per press`() {
    var matcher = gestureMatcher([.testRightOption, .testRightOption])
    var inputs: [GestureInput] = []

    for time in [Duration.zero, .milliseconds(100)] {
      if let input = matcher.receive(
        transition(
          .modifier(.rightOption), .down, [.modifier(.rightOption)], time: time,
        ),
      )
      .gestureInput {
        inputs.append(input)
      }
      if let input = matcher.receive(
        transition(
          .modifier(.rightOption), .up, [], time: time + .milliseconds(50),
        ),
      )
      .gestureInput {
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
      HotkeyBinding<TestAction>(hotkey: .testRightOption, route: .gesture),
      HotkeyBinding(hotkey: paste, route: .action(.pasteLastTranscript)),
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

    #expect(completion.output == .action(.pasteLastTranscript))
    #expect(completion.disposition == .suppress)
    #expect(release.output == nil)
    #expect(release.disposition == .suppress)
  }

  @Test func `global inputs remain distinct from route-owned gestures`() {
    var matcher = MultipleChordMatcher(bindings: [
      HotkeyBinding(
        hotkey: .testPasteLastTranscript, route: .action(TestAction.pasteLastTranscript),
      ),
    ])

    let escape = matcher.receive(
      transition(
        .keyCode(PhysicalKey.escapeKeyCode), .down, [.keyCode(PhysicalKey.escapeKeyCode)],
      ),
    )

    #expect(escape.output == .global(.escape))
  }

  @Test func `activation alternatives still route gestures beside an action binding`() {
    var matcher = MultipleChordMatcher(bindings: [
      HotkeyBinding<TestAction>(hotkey: .testRightOption, route: .gesture),
      HotkeyBinding(hotkey: .testPasteLastTranscript, route: .action(.pasteLastTranscript)),
    ])

    let activation = matcher.receive(
      transition(.modifier(.rightOption), .down, [.modifier(.rightOption)]),
    )
    let release = matcher.receive(
      transition(.modifier(.rightOption), .up, []),
    )

    #expect(activation.output == .gesture(.activation(at: .zero)))
    #expect(release.output == .gesture(.release(at: .zero)))
  }

  @Test func `building one alternative does not conflict with another`() throws {
    let controlR = try Hotkey(keyCode: 15, modifiers: [.rightControl])
    var matcher = gestureMatcher([.testRightOption, controlR])

    let partial = matcher.receive(
      transition(.modifier(.rightControl), .down, [.modifier(.rightControl)]),
    )
    #expect(partial.output == nil)
  }

  // MARK: Private

  private enum TestAction: Equatable { case pasteLastTranscript }

  private func gestureMatcher(_ hotkeys: [Hotkey]) -> MultipleChordMatcher<TestAction> {
    MultipleChordMatcher(
      bindings: hotkeys.map { HotkeyBinding(hotkey: $0, route: .gesture) },
    )
  }

  private func transition(
    _ key: PhysicalKey, _ phase: KeyPhase, _ pressedAfter: Set<PhysicalKey>,
    time: Duration = .zero,
  ) -> KeyTransition {
    KeyTransition(key: key, phase: phase, pressedAfter: pressedAfter, time: time)
  }
}

private extension RoutedChordMatch {
  var gestureInput: GestureInput? {
    guard case let .gesture(input) = output else {
      return nil
    }
    return input
  }
}
