import CoreGraphics
import Testing

@testable import HotkeyListener

@Suite struct PhysicalChordMatcherTests {
  @Test func modifierStateUsesDeviceSpecificEventFlags() {
    let downFlags: [(ModifierKey, CGEventFlags)] = [
      (.leftCommand, CGEventFlags(rawValue: 0x0000_0008)),
      (.rightCommand, CGEventFlags(rawValue: 0x0000_0010)),
      (.leftShift, CGEventFlags(rawValue: 0x0000_0002)),
      (.rightShift, CGEventFlags(rawValue: 0x0000_0004)),
      (.leftOption, CGEventFlags(rawValue: 0x0000_0020)),
      (.rightOption, CGEventFlags(rawValue: 0x0000_0040)),
      (.leftControl, CGEventFlags(rawValue: 0x0000_0001)),
      (.rightControl, CGEventFlags(rawValue: 0x0000_2000)), (.function, .maskSecondaryFn),
    ]

    for (modifier, flags) in downFlags { #expect(modifier.isDown(in: flags)) }
    let rightOptionFlags = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x40)
    let leftOptionFlags = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x20)
    #expect(!ModifierKey.leftOption.isDown(in: rightOptionFlags))
    #expect(!ModifierKey.rightOption.isDown(in: leftOptionFlags))
    #expect(!ModifierKey.rightOption.isDown(in: .maskAlternate))
  }

  @Test func configuredPhysicalSideIsMatched() {
    var matcher = PhysicalChordMatcher(hotkey: .rightOption)

    let leftOption = matcher.receive(
      transition(.modifier(.leftOption), .down, pressedAfter: [.modifier(.leftOption)]))
    #expect(leftOption.input == .conflict(at: .zero))
    #expect(leftOption.disposition == .passThrough)

    _ = matcher.receive(transition(.modifier(.leftOption), .up, pressedAfter: []))
    let rightOption = matcher.receive(
      transition(
        .modifier(.rightOption), .down, pressedAfter: [.modifier(.rightOption)],
        time: .milliseconds(100)))
    #expect(rightOption.input == .activation(at: .milliseconds(100)))
    #expect(rightOption.disposition == .passThrough)
  }

  @Test func modifierOnlyReleaseIsMatchedAndPassedThrough() {
    var matcher = PhysicalChordMatcher(hotkey: .rightOption)
    _ = matcher.receive(
      transition(.modifier(.rightOption), .down, pressedAfter: [.modifier(.rightOption)]))

    let release = matcher.receive(
      transition(.modifier(.rightOption), .up, pressedAfter: [], time: .milliseconds(500)))
    #expect(release.input == .release(at: .milliseconds(500)))
    #expect(release.disposition == .passThrough)
  }

  @Test func modifierOnlyChordNeverConsumesUnrelatedKeys() {
    var matcher = PhysicalChordMatcher(hotkey: .rightOption)
    _ = matcher.receive(
      transition(.modifier(.rightOption), .down, pressedAfter: [.modifier(.rightOption)]))

    let unrelatedKey = matcher.receive(
      transition(
        .keyCode(0), .down, pressedAfter: [.modifier(.rightOption), .keyCode(0)],
        time: .milliseconds(50)))
    #expect(unrelatedKey.input == .conflict(at: .milliseconds(50)))
    #expect(unrelatedKey.disposition == .passThrough)
  }

  @Test func modifierChordCanBeBuiltOneModifierAtATime() throws {
    let hotkey = try Hotkey(modifiers: [.leftCommand, .rightOption])
    var matcher = PhysicalChordMatcher(hotkey: hotkey)

    let partial = matcher.receive(
      transition(.modifier(.leftCommand), .down, pressedAfter: [.modifier(.leftCommand)]))
    #expect(partial.input == nil)

    let complete = matcher.receive(
      transition(
        .modifier(.rightOption), .down,
        pressedAfter: [.modifier(.leftCommand), .modifier(.rightOption)], time: .milliseconds(50)))
    #expect(complete.input == .activation(at: .milliseconds(50)))
  }

  @Test func addingAnExtraModifierConflictsWithoutReleasingActiveChord() {
    var matcher = PhysicalChordMatcher(hotkey: .rightOption)
    _ = matcher.receive(
      transition(.modifier(.rightOption), .down, pressedAfter: [.modifier(.rightOption)]))

    let conflict = matcher.receive(
      transition(
        .modifier(.leftShift), .down,
        pressedAfter: [.modifier(.rightOption), .modifier(.leftShift)], time: .milliseconds(100)))
    #expect(conflict.input == .conflict(at: .milliseconds(100)))

    let release = matcher.receive(
      transition(
        .modifier(.rightOption), .up, pressedAfter: [.modifier(.leftShift)],
        time: .milliseconds(200)))
    #expect(release.input == .release(at: .milliseconds(200)))
  }

  @Test func escapeIsRecognizedAndPassedThrough() {
    var matcher = PhysicalChordMatcher(hotkey: .rightOption)

    let escape = matcher.receive(
      transition(
        .keyCode(PhysicalKey.escapeKeyCode), .down,
        pressedAfter: [.keyCode(PhysicalKey.escapeKeyCode)]))
    #expect(escape.input == .escape)
    #expect(escape.disposition == .passThrough)
  }

  @Test func keyedChordSuppressesOnlyItsPrimaryKeyPair() throws {
    let hotkey = try Hotkey(keyCode: 0, modifiers: [.leftCommand])
    var matcher = PhysicalChordMatcher(hotkey: hotkey)

    let modifier = matcher.receive(
      transition(.modifier(.leftCommand), .down, pressedAfter: [.modifier(.leftCommand)]))
    #expect(modifier.input == nil)
    #expect(modifier.disposition == .passThrough)

    let keyDown = matcher.receive(
      transition(
        .keyCode(0), .down, pressedAfter: [.modifier(.leftCommand), .keyCode(0)],
        time: .milliseconds(10)))
    #expect(keyDown.input == .activation(at: .milliseconds(10)))
    #expect(keyDown.disposition == .suppress)

    let repeatKey = matcher.receive(
      transition(
        .keyCode(0), .down, isRepeat: true, pressedAfter: [.modifier(.leftCommand), .keyCode(0)],
        time: .milliseconds(20)))
    #expect(repeatKey.input == nil)
    #expect(repeatKey.disposition == .suppress)

    let keyUp = matcher.receive(
      transition(
        .keyCode(0), .up, pressedAfter: [.modifier(.leftCommand)], time: .milliseconds(500)))
    #expect(keyUp.input == .release(at: .milliseconds(500)))
    #expect(keyUp.disposition == .suppress)
  }

  @Test func keyedChordDoesNotSuppressPrimaryKeyWithWrongModifiers() throws {
    let hotkey = try Hotkey(keyCode: 0, modifiers: [.leftCommand])
    var matcher = PhysicalChordMatcher(hotkey: hotkey)

    let keyDown = matcher.receive(transition(.keyCode(0), .down, pressedAfter: [.keyCode(0)]))
    #expect(keyDown.input == nil)
    #expect(keyDown.disposition == .passThrough)
  }

  @Test func keyedChordReleasesWhenPrimaryKeyLiftsAfterModifier() throws {
    let hotkey = try Hotkey(keyCode: 0, modifiers: [.leftCommand])
    var matcher = PhysicalChordMatcher(hotkey: hotkey)
    _ = matcher.receive(
      transition(.modifier(.leftCommand), .down, pressedAfter: [.modifier(.leftCommand)]))
    _ = matcher.receive(
      transition(.keyCode(0), .down, pressedAfter: [.modifier(.leftCommand), .keyCode(0)]))

    let modifierUp = matcher.receive(
      transition(.modifier(.leftCommand), .up, pressedAfter: [.keyCode(0)]))
    #expect(modifierUp.input == nil)
    #expect(modifierUp.disposition == .passThrough)

    let keyUp = matcher.receive(
      transition(.keyCode(0), .up, pressedAfter: [], time: .milliseconds(500)))
    #expect(keyUp.input == .release(at: .milliseconds(500)))
    #expect(keyUp.disposition == .suppress)
  }

  @Test func interruptionPreservesSuppressionUntilPairedKeyUp() throws {
    let hotkey = try Hotkey(keyCode: 0, modifiers: [.leftCommand])
    var matcher = PhysicalChordMatcher(hotkey: hotkey)
    _ = matcher.receive(
      transition(.keyCode(0), .down, pressedAfter: [.modifier(.leftCommand), .keyCode(0)]))

    matcher.interrupt()
    let keyUp = matcher.receive(transition(.keyCode(0), .up, pressedAfter: []))
    #expect(keyUp.input == .neutral)
    #expect(keyUp.disposition == .suppress)
  }

  private func transition(
    _ key: PhysicalKey, _ phase: KeyPhase, isRepeat: Bool = false, pressedAfter: Set<PhysicalKey>,
    time: Duration = .zero
  ) -> KeyTransition {
    KeyTransition(
      key: key, phase: phase, isRepeat: isRepeat, pressedAfter: pressedAfter, time: time)
  }
}
