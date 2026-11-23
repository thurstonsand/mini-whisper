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

  @Test func `Return ends a live recording and the field never sees any of it`() {
    var matcher = gestureMatcher([.testRightOption])
    _ = matcher.receive(transition(.modifier(.rightOption), .down, [.modifier(.rightOption)]))
    matcher.submitKeyArmed = true

    let held: Set<PhysicalKey> = [.modifier(.rightOption), .keyCode(36)]
    let press = matcher.receive(transition(.keyCode(36), .down, held, time: .seconds(1)))
    // The recording it ended disarms the key before the rest of the keystroke arrives.
    matcher.submitKeyArmed = false
    let repeated = matcher.receive(
      KeyTransition(
        key: .keyCode(36),
        phase: .down,
        isRepeat: true,
        pressedAfter: held,
        time: .seconds(1),
      ),
    )
    let lift = matcher.receive(transition(.keyCode(36), .up, [.modifier(.rightOption)]))

    #expect(press == RoutedChordMatch(output: .gesture(.submitKey), disposition: .suppress))
    #expect(repeated == RoutedChordMatch(output: nil, disposition: .suppress))
    #expect(lift == RoutedChordMatch(output: nil, disposition: .suppress))
  }

  @Test func `Return outside a recording is the field's`() {
    var matcher = gestureMatcher([.testRightOption])

    let press = matcher.receive(transition(.keyCode(36), .down, [.keyCode(36)]))
    let lift = matcher.receive(transition(.keyCode(36), .up, []))

    #expect(press.output != .gesture(.submitKey))
    #expect(press.disposition == .passThrough)
    #expect(lift.disposition == .passThrough)
  }

  @Test func `building one alternative does not conflict with another`() throws {
    let controlR = try Hotkey(keyCode: 15, modifiers: [.rightControl])
    var matcher = gestureMatcher([.testRightOption, controlR])

    let partial = matcher.receive(
      transition(.modifier(.rightControl), .down, [.modifier(.rightControl)]),
    )
    #expect(partial.output == nil)
  }

  @Test func `a key-up the tap never saw does not block the next activation`() {
    var tap = RecordingTap(matcher: gestureMatcher([.testRightOption]))

    // Q goes down; its key-up is lost behind a lock screen.
    _ = tap.press(.keyCode(12), .down, at: .zero, keyboard: [.keyCode(12)])
    let option = tap.press(
      .modifier(.rightOption), .down, at: .seconds(5), keyboard: [.modifier(.rightOption)],
    )

    #expect(option.gestureInput == .activation(at: .seconds(5)))
    #expect(tap.held.keys == [.modifier(.rightOption)])
  }

  /// The callback can trail the keyboard: Q's key-up may still be queued behind this Option.
  @Test func `a key-up still on its way keeps the chord in conflict`() {
    var tap = RecordingTap(matcher: gestureMatcher([.testRightOption]))

    _ = tap.press(.keyCode(12), .down, at: .zero, keyboard: [.keyCode(12)])
    let option = tap.press(
      .modifier(.rightOption), .down, at: .milliseconds(80), keyboard: [.modifier(.rightOption)],
    )

    #expect(option.gestureInput == nil)
    #expect(tap.held.keys == [.keyCode(12), .modifier(.rightOption)])
  }

  @Test func `a fresh press of a key whose release was lost starts over`() {
    var tap = RecordingTap(matcher: gestureMatcher([.testRightOption]))
    let returnKey = PhysicalKey.keyCode(36)
    tap.matcher.submitKeyArmed = true
    #expect(tap.press(returnKey, .down, at: .zero, keyboard: [returnKey]).disposition == .suppress)
    tap.matcher.submitKeyArmed = false

    let repeated = tap.press(returnKey, .down, repeat: true, at: .milliseconds(500), keyboard: [])
    let fresh = tap.press(returnKey, .down, at: .milliseconds(600), keyboard: [returnKey])

    #expect(repeated.disposition == .suppress)
    #expect(fresh.disposition == .passThrough)
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

// MARK: - RecordingTap

/// What the event tap does with each key event: settle the held keys, then route.
private struct RecordingTap<Action: Equatable & Sendable> {
  var matcher: MultipleChordMatcher<Action>
  var held = HeldKeys()

  mutating func press(
    _ key: PhysicalKey, _ phase: KeyPhase, repeat isRepeat: Bool = false, at time: Duration,
    keyboard: Set<PhysicalKey>,
  ) -> RoutedChordMatch<Action> {
    let (releases, transition) = held.record(
      key, phase, isRepeat: isRepeat, time: time, isHeld: keyboard.contains,
    )
    for release in releases {
      _ = matcher.receive(release)
    }
    return matcher.receive(transition)
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
