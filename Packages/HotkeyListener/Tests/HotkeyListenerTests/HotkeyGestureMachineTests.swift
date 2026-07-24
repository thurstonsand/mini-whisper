import Testing

@testable import HotkeyListener

@Suite struct HotkeyGestureMachineTests {
  @Test func holdStartsAndStopsRecording() {
    var machine = HotkeyGestureMachine()

    #expect(machine.receive(.activation(at: .zero)) == .startRecording)
    #expect(machine.phase == .holding(startedAt: .zero))
    #expect(machine.receive(.release(at: .seconds(1))) == .stopAndTranscribe)
    #expect(machine.phase == .idle)
  }

  @Test func loneTapIsAnImmediateStartAndStop() {
    var machine = HotkeyGestureMachine()

    #expect(machine.receive(.activation(at: .zero)) == .startRecording)
    #expect(machine.receive(.release(at: .milliseconds(20))) == .stopAndTranscribe)
    #expect(machine.phase == .idle)
  }

  @Test func doubleTapEngagesLatchOnSecondRelease() {
    var machine = HotkeyGestureMachine()

    #expect(machine.receive(.activation(at: .zero)) == .startRecording)
    #expect(machine.receive(.release(at: .milliseconds(50))) == .stopAndTranscribe)
    #expect(machine.receive(.activation(at: .milliseconds(100))) == .startRecording)
    #expect(machine.phase == .holding(startedAt: .milliseconds(100)))
    #expect(machine.receive(.release(at: .milliseconds(200))) == .latchEngaged)
    #expect(machine.phase == .latched)
  }

  @Test func latchedTapStopsImmediatelyAndRearmsOnRelease() {
    var machine = latchedMachine()

    #expect(machine.receive(.activation(at: .seconds(1))) == .stopAndTranscribe)
    #expect(machine.phase == .blockedUntilRelease)
    #expect(machine.receive(.release(at: .seconds(1) + .milliseconds(10))) == nil)
    #expect(machine.phase == .idle)
  }

  @Test func releaseGapJustInsideThresholdLatches() {
    var machine = HotkeyGestureMachine()

    _ = machine.receive(.activation(at: .zero))
    _ = machine.receive(.release(at: .milliseconds(100)))
    _ = machine.receive(.activation(at: .milliseconds(200)))

    #expect(machine.receive(.release(at: .milliseconds(399))) == .latchEngaged)
    #expect(machine.phase == .latched)
  }

  @Test func releaseGapAtThresholdDoesNotLatch() {
    var machine = HotkeyGestureMachine()

    _ = machine.receive(.activation(at: .zero))
    _ = machine.receive(.release(at: .milliseconds(100)))
    _ = machine.receive(.activation(at: .milliseconds(200)))

    #expect(machine.receive(.release(at: .milliseconds(400))) == .stopAndTranscribe)
    #expect(machine.phase == .idle)
  }

  @Test func releaseGapOutsideThresholdDoesNotLatch() {
    var machine = HotkeyGestureMachine()

    _ = machine.receive(.activation(at: .zero))
    _ = machine.receive(.release(at: .milliseconds(100)))
    _ = machine.receive(.activation(at: .milliseconds(200)))

    #expect(machine.receive(.release(at: .milliseconds(401))) == .stopAndTranscribe)
    #expect(machine.phase == .idle)
  }

  @Test func longSecondTapBecomesAnOrdinaryHold() {
    var machine = HotkeyGestureMachine()

    _ = machine.receive(.activation(at: .zero))
    _ = machine.receive(.release(at: .milliseconds(100)))
    _ = machine.receive(.activation(at: .milliseconds(200)))

    #expect(machine.receive(.release(at: .seconds(2))) == .stopAndTranscribe)
    #expect(machine.phase == .idle)
  }

  @Test func escapeWhileIdleBlocksWithoutInventingCancellation() {
    var machine = HotkeyGestureMachine()

    #expect(machine.receive(.escape) == nil)
    #expect(machine.phase == .blockedUntilRelease)
    #expect(machine.receive(.neutral) == nil)
    #expect(machine.phase == .idle)
  }

  @Test func escapeCancelsHoldAndPreventsBackslide() {
    var machine = HotkeyGestureMachine()
    _ = machine.receive(.activation(at: .zero))

    #expect(machine.receive(.escape) == .cancel)
    #expect(machine.phase == .blockedUntilRelease)
    #expect(machine.receive(.activation(at: .milliseconds(100))) == nil)
    #expect(machine.receive(.neutral) == nil)
    #expect(machine.receive(.activation(at: .milliseconds(200))) == .startRecording)
  }

  @Test func escapeCancelsLatch() {
    var machine = latchedMachine()

    #expect(machine.receive(.escape) == .cancel)
    #expect(machine.phase == .blockedUntilRelease)
  }

  @Test func repeatedEscapeWhileBlockedDoesNotEmitCancellation() {
    var machine = HotkeyGestureMachine()

    #expect(machine.receive(.escape) == nil)
    #expect(machine.receive(.escape) == nil)
  }

  @Test func interruptionCancelsHoldAndFailsClosed() {
    var machine = HotkeyGestureMachine()
    _ = machine.receive(.activation(at: .zero))

    #expect(machine.receive(.monitoringInterrupted) == .cancel)
    #expect(machine.phase == .blockedUntilRelease)
    #expect(machine.receive(.activation(at: .milliseconds(100))) == nil)
    #expect(machine.receive(.release(at: .milliseconds(200))) == nil)
    #expect(machine.phase == .idle)
  }

  @Test func interruptionCancelsLatchAndFailsClosed() {
    var machine = latchedMachine()

    #expect(machine.receive(.monitoringInterrupted) == .cancel)
    #expect(machine.phase == .blockedUntilRelease)
    #expect(machine.receive(.neutral) == nil)
    #expect(machine.phase == .idle)
  }

  @Test func interruptionWhileIdleDoesNotInventCancellation() {
    var machine = HotkeyGestureMachine()

    #expect(machine.receive(.monitoringInterrupted) == nil)
    #expect(machine.phase == .blockedUntilRelease)
  }

  @Test func earlyConflictingInputCancelsAndBlocks() {
    var machine = HotkeyGestureMachine()
    _ = machine.receive(.activation(at: .zero))

    #expect(machine.receive(.conflict(at: .milliseconds(299))) == .cancel)
    #expect(machine.phase == .blockedUntilRelease)
  }

  @Test func conflictingInputAtAccidentalWindowIsIgnored() {
    var machine = HotkeyGestureMachine()
    _ = machine.receive(.activation(at: .zero))

    #expect(machine.receive(.conflict(at: .milliseconds(300))) == nil)
    #expect(machine.phase == .holding(startedAt: .zero))
  }

  @Test func earlyMouseDownCancelsButMouseDownDuringLatchDoesNot() {
    var holding = HotkeyGestureMachine()
    _ = holding.receive(.activation(at: .zero))
    #expect(holding.receive(.mouseDown(at: .milliseconds(100))) == .cancel)

    var latched = latchedMachine()
    #expect(latched.receive(.mouseDown(at: .seconds(1))) == nil)
    #expect(latched.phase == .latched)
  }

  @Test func idleMouseDownDoesNotBlockTheNextActivation() {
    var machine = HotkeyGestureMachine()

    #expect(machine.receive(.mouseDown(at: .zero)) == nil)
    #expect(machine.phase == .idle)
    #expect(machine.receive(.activation(at: .milliseconds(100))) == .startRecording)
  }

  @Test func initiallyBlockedMachineRequiresNeutralInput() {
    var machine = HotkeyGestureMachine(initiallyBlocked: true)

    #expect(machine.receive(.activation(at: .zero)) == nil)
    #expect(machine.receive(.neutral) == nil)
    #expect(machine.receive(.activation(at: .milliseconds(100))) == .startRecording)
  }

  private func latchedMachine() -> HotkeyGestureMachine {
    var machine = HotkeyGestureMachine()
    _ = machine.receive(.activation(at: .zero))
    _ = machine.receive(.release(at: .milliseconds(50)))
    _ = machine.receive(.activation(at: .milliseconds(100)))
    _ = machine.receive(.release(at: .milliseconds(200)))
    return machine
  }
}
