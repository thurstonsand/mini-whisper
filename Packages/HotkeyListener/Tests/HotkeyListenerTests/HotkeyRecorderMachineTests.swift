@testable import HotkeyListener
import Testing

struct HotkeyRecorderMachineTests {
  // MARK: Internal

  @Test func `live chord commits after every key is released`() throws {
    var machine = HotkeyRecorderMachine()
    let modifier = PhysicalKey.modifier(.rightControl)
    let key = PhysicalKey.keyCode(15)

    #expect(
      machine.receive(transition(modifier, .down, [modifier]))
        == .chordChanged(HotkeyRecordingChord(modifiers: [.rightControl])),
    )
    #expect(
      machine.receive(transition(key, .down, [modifier, key]))
        == .chordChanged(
          HotkeyRecordingChord(keyCodes: [15], modifiers: [.rightControl]),
        ),
    )
    #expect(machine.receive(transition(modifier, .up, [key])) == nil)
    #expect(
      try machine.receive(transition(key, .up, []))
        == .committed(Hotkey(keyCode: 15, modifiers: [.rightControl])),
    )
  }

  @Test func `escape cancels instead of becoming a binding`() {
    var machine = HotkeyRecorderMachine()
    let escape = PhysicalKey.keyCode(PhysicalKey.escapeKeyCode)

    #expect(machine.receive(transition(escape, .down, [escape])) == .cancelled)
  }

  @Test func `multiple ordinary keys are rejected and recording rearms`() {
    var machine = HotkeyRecorderMachine()
    let first = PhysicalKey.keyCode(0)
    let second = PhysicalKey.keyCode(1)
    _ = machine.receive(transition(first, .down, [first]))
    _ = machine.receive(transition(second, .down, [first, second]))
    _ = machine.receive(transition(first, .up, [second]))

    #expect(
      machine.receive(transition(second, .up, [])) == .validationFailed(.multipleKeys),
    )
    let option = PhysicalKey.modifier(.rightOption)
    _ = machine.receive(transition(option, .down, [option]))
    #expect(machine.receive(transition(option, .up, [])) == .committed(.testRightOption))
  }

  @Test func `an up for A key never witnessed down is ignored`() {
    var machine = HotkeyRecorderMachine()
    let staleKey = PhysicalKey.keyCode(127)
    let option = PhysicalKey.modifier(.rightOption)

    #expect(machine.receive(transition(staleKey, .up, [])) == nil)
    #expect(
      machine.receive(transition(option, .down, [option]))
        == .chordChanged(HotkeyRecordingChord(modifiers: [.rightOption])),
    )
    #expect(machine.receive(transition(option, .up, [])) == .committed(.testRightOption))
  }

  // MARK: Private

  private func transition(
    _ key: PhysicalKey, _ phase: KeyPhase, _ pressedAfter: Set<PhysicalKey>,
  ) -> KeyTransition {
    KeyTransition(key: key, phase: phase, pressedAfter: pressedAfter, time: .zero)
  }
}
