@testable import HotkeyListener
import Testing

struct HotkeyGestureMachineTests {
  // MARK: Internal

  @Test func `hold starts and stops recording`() {
    var machine = HotkeyGestureMachine()

    #expect(machine.receive(.activation(at: .zero)) == .startRecording)
    #expect(machine.phase == .holding(startedAt: .zero))
    #expect(machine.receive(.release(at: .seconds(1))) == .stopAndTranscribe)
    #expect(machine.phase == .idle)
  }

  @Test func `lone tap is an immediate start and stop`() {
    var machine = HotkeyGestureMachine()

    #expect(machine.receive(.activation(at: .zero)) == .startRecording)
    #expect(machine.receive(.release(at: .milliseconds(20))) == .stopAndTranscribe)
    #expect(machine.phase == .idle)
  }

  @Test func `double tap engages latch on second release`() {
    var machine = HotkeyGestureMachine()

    #expect(machine.receive(.activation(at: .zero)) == .startRecording)
    #expect(machine.receive(.release(at: .milliseconds(50))) == .stopAndTranscribe)
    #expect(machine.receive(.activation(at: .milliseconds(100))) == .startRecording)
    #expect(machine.phase == .holding(startedAt: .milliseconds(100)))
    #expect(machine.receive(.release(at: .milliseconds(200))) == .latchEngaged)
    #expect(machine.phase == .latched)
  }

  @Test func `latched tap stops immediately and rearms on release`() {
    var machine = latchedMachine()

    #expect(machine.receive(.activation(at: .seconds(1))) == .stopAndTranscribe)
    #expect(machine.phase == .blockedUntilRelease)
    #expect(machine.receive(.release(at: .seconds(1) + .milliseconds(10))) == nil)
    #expect(machine.phase == .idle)
  }

  @Test func `release gap just inside threshold latches`() {
    var machine = HotkeyGestureMachine()

    _ = machine.receive(.activation(at: .zero))
    _ = machine.receive(.release(at: .milliseconds(100)))
    _ = machine.receive(.activation(at: .milliseconds(200)))

    #expect(machine.receive(.release(at: .milliseconds(399))) == .latchEngaged)
    #expect(machine.phase == .latched)
  }

  @Test func `release gap at threshold does not latch`() {
    var machine = HotkeyGestureMachine()

    _ = machine.receive(.activation(at: .zero))
    _ = machine.receive(.release(at: .milliseconds(100)))
    _ = machine.receive(.activation(at: .milliseconds(200)))

    #expect(machine.receive(.release(at: .milliseconds(400))) == .stopAndTranscribe)
    #expect(machine.phase == .idle)
  }

  @Test func `release gap outside threshold does not latch`() {
    var machine = HotkeyGestureMachine()

    _ = machine.receive(.activation(at: .zero))
    _ = machine.receive(.release(at: .milliseconds(100)))
    _ = machine.receive(.activation(at: .milliseconds(200)))

    #expect(machine.receive(.release(at: .milliseconds(401))) == .stopAndTranscribe)
    #expect(machine.phase == .idle)
  }

  @Test func `long second tap becomes an ordinary hold`() {
    var machine = HotkeyGestureMachine()

    _ = machine.receive(.activation(at: .zero))
    _ = machine.receive(.release(at: .milliseconds(100)))
    _ = machine.receive(.activation(at: .milliseconds(200)))

    #expect(machine.receive(.release(at: .seconds(2))) == .stopAndTranscribe)
    #expect(machine.phase == .idle)
  }

  @Test func `escape while idle blocks without inventing cancellation`() {
    var machine = HotkeyGestureMachine()

    #expect(machine.receive(.escape) == nil)
    #expect(machine.phase == .blockedUntilRelease)
    #expect(machine.receive(.neutral) == nil)
    #expect(machine.phase == .idle)
  }

  @Test func `escape cancels hold and prevents backslide`() {
    var machine = HotkeyGestureMachine()
    _ = machine.receive(.activation(at: .zero))

    #expect(machine.receive(.escape) == .cancel)
    #expect(machine.phase == .blockedUntilRelease)
    #expect(machine.receive(.activation(at: .milliseconds(100))) == nil)
    #expect(machine.receive(.neutral) == nil)
    #expect(machine.receive(.activation(at: .milliseconds(200))) == .startRecording)
  }

  @Test func `escape cancels latch`() {
    var machine = latchedMachine()

    #expect(machine.receive(.escape) == .cancel)
    #expect(machine.phase == .blockedUntilRelease)
  }

  @Test func `repeated escape while blocked does not emit cancellation`() {
    var machine = HotkeyGestureMachine()

    #expect(machine.receive(.escape) == nil)
    #expect(machine.receive(.escape) == nil)
  }

  @Test func `interruption cancels hold and fails closed`() {
    var machine = HotkeyGestureMachine()
    _ = machine.receive(.activation(at: .zero))

    #expect(machine.receive(.monitoringInterrupted) == .cancel)
    #expect(machine.phase == .blockedUntilRelease)
    #expect(machine.receive(.activation(at: .milliseconds(100))) == nil)
    #expect(machine.receive(.release(at: .milliseconds(200))) == nil)
    #expect(machine.phase == .idle)
  }

  @Test func `interruption cancels latch and fails closed`() {
    var machine = latchedMachine()

    #expect(machine.receive(.monitoringInterrupted) == .cancel)
    #expect(machine.phase == .blockedUntilRelease)
    #expect(machine.receive(.neutral) == nil)
    #expect(machine.phase == .idle)
  }

  @Test func `interruption while idle does not invent cancellation`() {
    var machine = HotkeyGestureMachine()

    #expect(machine.receive(.monitoringInterrupted) == nil)
    #expect(machine.phase == .blockedUntilRelease)
  }

  @Test func `early conflicting input cancels and blocks`() {
    var machine = HotkeyGestureMachine()
    _ = machine.receive(.activation(at: .zero))

    #expect(machine.receive(.conflict(at: .milliseconds(299))) == .cancel)
    #expect(machine.phase == .blockedUntilRelease)
  }

  @Test func `conflicting input at accidental window is ignored`() {
    var machine = HotkeyGestureMachine()
    _ = machine.receive(.activation(at: .zero))

    #expect(machine.receive(.conflict(at: .milliseconds(300))) == nil)
    #expect(machine.phase == .holding(startedAt: .zero))
  }

  @Test func `early mouse down cancels but mouse down during latch does not`() {
    var holding = HotkeyGestureMachine()
    _ = holding.receive(.activation(at: .zero))
    #expect(holding.receive(.mouseDown(at: .milliseconds(100))) == .cancel)

    var latched = latchedMachine()
    #expect(latched.receive(.mouseDown(at: .seconds(1))) == nil)
    #expect(latched.phase == .latched)
  }

  @Test func `idle mouse down does not block the next activation`() {
    var machine = HotkeyGestureMachine()

    #expect(machine.receive(.mouseDown(at: .zero)) == nil)
    #expect(machine.phase == .idle)
    #expect(machine.receive(.activation(at: .milliseconds(100))) == .startRecording)
  }

  @Test func `initially blocked machine requires neutral input`() {
    var machine = HotkeyGestureMachine(initiallyBlocked: true)

    #expect(machine.receive(.activation(at: .zero)) == nil)
    #expect(machine.receive(.neutral) == nil)
    #expect(machine.receive(.activation(at: .milliseconds(100))) == .startRecording)
  }

  // MARK: Private

  private func latchedMachine() -> HotkeyGestureMachine {
    var machine = HotkeyGestureMachine()
    _ = machine.receive(.activation(at: .zero))
    _ = machine.receive(.release(at: .milliseconds(50)))
    _ = machine.receive(.activation(at: .milliseconds(100)))
    _ = machine.receive(.release(at: .milliseconds(200)))
    return machine
  }
}
