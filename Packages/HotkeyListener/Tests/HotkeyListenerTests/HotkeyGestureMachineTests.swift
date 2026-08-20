@testable import HotkeyListener
import Testing

struct HotkeyGestureMachineTests {
  // MARK: Internal

  @Test func `idle input table`() {
    assertCell(idle, .activation(at: .zero), .startRecording, .holding(startedAt: .zero))
    assertCell(idle, .release(at: .milliseconds(100)), nil, .idle)
    assertCell(idle, .release(at: .milliseconds(200)), nil, .idle)
    assertCell(idle, .conflict(at: .milliseconds(100)), nil, .blockedUntilRelease)
    assertCell(idle, .conflict(at: .milliseconds(300)), nil, .blockedUntilRelease)
    assertCell(idle, .mouseDown(at: .milliseconds(100)), nil, .idle)
    assertCell(idle, .escape, nil, .blockedUntilRelease)
    assertCell(idle, .deadlineElapsed, nil, .idle)
    assertCell(idle, .monitoringInterrupted, nil, .blockedUntilRelease)
    assertCell(idle, .cleanupStarted, nil, .cleanupPending)
    assertCell(idle, .cleanupEnded, nil, .idle)
  }

  @Test func `holding input table`() {
    assertCell(holding, .activation(at: .milliseconds(100)), nil, .holding(startedAt: .zero))
    assertCell(
      holding, .release(at: .milliseconds(199)), nil,
      .provisional(releasedAt: .milliseconds(199)),
    )
    assertCell(holding, .release(at: .milliseconds(200)), .stopAndTranscribe, .idle)
    assertCell(
      holding, .conflict(at: .milliseconds(299)), .discardRecording, .blockedUntilRelease,
    )
    assertCell(
      holding, .conflict(at: .milliseconds(300)), nil, .holding(startedAt: .zero),
    )
    assertCell(
      holding, .mouseDown(at: .milliseconds(100)), .discardRecording, .blockedUntilRelease,
    )
    assertCell(holding, .escape, .cancelAndArchive, .blockedUntilRelease)
    assertCell(holding, .deadlineElapsed, nil, .holding(startedAt: .zero))
    assertCell(holding, .monitoringInterrupted, .cancelAndArchive, .blockedUntilRelease)
    // A press has already taken the key's meaning; a late cleanup notice cannot take it back.
    assertCell(holding, .cleanupStarted, nil, .holding(startedAt: .zero))
    assertCell(holding, .cleanupEnded, nil, .holding(startedAt: .zero))
  }

  @Test func `provisional input table`() {
    assertCell(
      provisional, .activation(at: .milliseconds(399)), nil,
      .secondPress(startedAt: .milliseconds(399)),
    )
    assertCell(
      provisional, .release(at: .milliseconds(150)), nil,
      .provisional(releasedAt: .milliseconds(100)),
    )
    assertCell(
      provisional, .release(at: .milliseconds(500)), nil,
      .provisional(releasedAt: .milliseconds(100)),
    )
    assertCell(
      provisional, .conflict(at: .milliseconds(200)), .discardRecording, .blockedUntilRelease,
    )
    assertCell(
      provisional, .conflict(at: .milliseconds(500)), .discardRecording, .blockedUntilRelease,
    )
    assertCell(
      provisional, .mouseDown(at: .milliseconds(200)), .discardRecording, .blockedUntilRelease,
    )
    assertCell(provisional, .escape, .discardRecording, .blockedUntilRelease)
    assertCell(provisional, .deadlineElapsed, .discardRecording, .idle)
    assertCell(provisional, .monitoringInterrupted, .discardRecording, .blockedUntilRelease)
    assertCell(
      provisional, .cleanupStarted, nil, .provisional(releasedAt: .milliseconds(100)),
    )
    assertCell(provisional, .cleanupEnded, nil, .provisional(releasedAt: .milliseconds(100)))
  }

  @Test func `second press input table`() {
    assertCell(
      secondPress, .activation(at: .milliseconds(250)), nil,
      .secondPress(startedAt: .milliseconds(200)),
    )
    assertCell(secondPress, .release(at: .milliseconds(399)), .latchEngaged, .latched)
    assertCell(secondPress, .release(at: .milliseconds(400)), .stopAndTranscribe, .idle)
    assertCell(
      secondPress, .conflict(at: .milliseconds(499)), .discardRecording,
      .blockedUntilRelease,
    )
    assertCell(
      secondPress, .conflict(at: .milliseconds(500)), nil,
      .secondPress(startedAt: .milliseconds(200)),
    )
    assertCell(
      secondPress, .mouseDown(at: .milliseconds(250)), .discardRecording,
      .blockedUntilRelease,
    )
    assertCell(secondPress, .escape, .cancelAndArchive, .blockedUntilRelease)
    assertCell(
      secondPress, .deadlineElapsed, nil, .secondPress(startedAt: .milliseconds(200)),
    )
    assertCell(secondPress, .monitoringInterrupted, .cancelAndArchive, .blockedUntilRelease)
    assertCell(secondPress, .cleanupStarted, nil, .secondPress(startedAt: .milliseconds(200)))
    assertCell(secondPress, .cleanupEnded, nil, .secondPress(startedAt: .milliseconds(200)))
  }

  @Test func `latched input table`() {
    assertCell(latched, .activation(at: .seconds(1)), .stopAndTranscribe, .blockedUntilRelease)
    assertCell(latched, .release(at: .milliseconds(100)), nil, .latched)
    assertCell(latched, .release(at: .milliseconds(500)), nil, .latched)
    assertCell(latched, .conflict(at: .milliseconds(100)), nil, .latched)
    assertCell(latched, .conflict(at: .milliseconds(500)), nil, .latched)
    assertCell(latched, .mouseDown(at: .milliseconds(100)), nil, .latched)
    assertCell(latched, .escape, .cancelAndArchive, .blockedUntilRelease)
    assertCell(latched, .deadlineElapsed, nil, .latched)
    assertCell(latched, .monitoringInterrupted, .cancelAndArchive, .blockedUntilRelease)
    assertCell(latched, .cleanupStarted, nil, .latched)
    assertCell(latched, .cleanupEnded, nil, .latched)
  }

  @Test func `blocked input table`() {
    assertCell(blocked, .activation(at: .milliseconds(100)), nil, .blockedUntilRelease)
    assertCell(blocked, .release(at: .milliseconds(100)), nil, .idle)
    assertCell(blocked, .release(at: .milliseconds(500)), nil, .idle)
    assertCell(blocked, .conflict(at: .milliseconds(100)), nil, .blockedUntilRelease)
    assertCell(blocked, .conflict(at: .milliseconds(500)), nil, .blockedUntilRelease)
    assertCell(blocked, .mouseDown(at: .milliseconds(100)), nil, .blockedUntilRelease)
    assertCell(blocked, .escape, nil, .blockedUntilRelease)
    assertCell(blocked, .deadlineElapsed, nil, .blockedUntilRelease)
    assertCell(blocked, .monitoringInterrupted, nil, .blockedUntilRelease)
    assertCell(blocked, .cleanupStarted, nil, .blockedUntilRelease)
    assertCell(blocked, .cleanupEnded, nil, .blockedUntilRelease)
  }

  @Test func `cleanup pending input table`() {
    assertCell(
      cleanupPending, .activation(at: .seconds(1)), .skipCleanupAndRecord,
      .holding(startedAt: .seconds(1)),
    )
    assertCell(cleanupPending, .release(at: .seconds(1)), nil, .cleanupPending)
    assertCell(cleanupPending, .conflict(at: .seconds(1)), nil, .cleanupPending)
    assertCell(cleanupPending, .mouseDown(at: .seconds(1)), nil, .cleanupPending)
    assertCell(cleanupPending, .escape, .cancelAndArchive, .blockedUntilRelease)
    assertCell(cleanupPending, .deadlineElapsed, nil, .cleanupPending)
    assertCell(cleanupPending, .monitoringInterrupted, nil, .blockedUntilRelease)
    assertCell(cleanupPending, .cleanupStarted, nil, .cleanupPending)
    assertCell(cleanupPending, .cleanupEnded, nil, .idle)
  }

  @Test func `a skip leaves the press behaving exactly as it would have from idle`() {
    var machine = cleanupPending()
    #expect(machine.receive(.activation(at: .seconds(1))) == .skipCleanupAndRecord)
    // A tap: the recording the press started goes on to discard itself, wordlessly.
    #expect(machine.receive(.release(at: .seconds(1) + .milliseconds(100))) == nil)
    #expect(machine.receive(.deadlineElapsed) == .discardRecording)
    #expect(machine.phase == .idle)
  }

  @Test func `a hold that skipped keeps recording until it is released`() {
    var machine = cleanupPending()
    #expect(machine.receive(.activation(at: .seconds(1))) == .skipCleanupAndRecord)
    #expect(machine.receive(.release(at: .seconds(2))) == .stopAndTranscribe)
    #expect(machine.phase == .idle)
  }

  @Test func `tap at two hundred milliseconds is A hold`() {
    var machine = HotkeyGestureMachine()
    #expect(machine.receive(.activation(at: .zero)) == .startRecording)
    #expect(machine.receive(.release(at: .milliseconds(200))) == .stopAndTranscribe)
    #expect(machine.phase == .idle)
  }

  @Test func `late mouse input preserves an established press`() {
    assertCell(
      holding, .mouseDown(at: .milliseconds(300)), nil, .holding(startedAt: .zero),
    )
    assertCell(
      secondPress, .mouseDown(at: .milliseconds(500)), nil,
      .secondPress(startedAt: .milliseconds(200)),
    )
  }

  @Test func `second press at three hundred milliseconds does not latch`() {
    var machine = provisional()
    #expect(machine.receive(.activation(at: .milliseconds(400))) == .discardRecording)
    #expect(machine.phase == .blockedUntilRelease)
  }

  @Test func `provisional expiry discards`() {
    var machine = provisional()
    #expect(machine.receive(.deadlineElapsed) == .discardRecording)
    #expect(machine.phase == .idle)
  }

  @Test func `tap then hold transcribes the whole capture`() {
    var machine = provisional()
    #expect(machine.receive(.activation(at: .milliseconds(200))) == nil)
    #expect(machine.receive(.release(at: .milliseconds(400))) == .stopAndTranscribe)
    #expect(machine.phase == .idle)
  }

  @Test func `double tap latches without restarting capture`() {
    var machine = provisional()
    #expect(machine.receive(.activation(at: .milliseconds(200))) == nil)
    #expect(machine.receive(.release(at: .milliseconds(399))) == .latchEngaged)
    #expect(machine.phase == .latched)
  }

  @Test func `latch press transcribes and swallows its release`() {
    var machine = latched()
    #expect(machine.receive(.activation(at: .seconds(1))) == .stopAndTranscribe)
    #expect(machine.receive(.release(at: .seconds(1) + .milliseconds(10))) == nil)
    #expect(machine.phase == .idle)
  }

  @Test func `neutral rearms every blocked interaction`() {
    var machine = holding()
    _ = machine.receive(.escape)
    #expect(machine.receive(.neutral) == nil)
    #expect(machine.phase == .idle)
  }

  // MARK: Private

  private func assertCell(
    _ makeMachine: () -> HotkeyGestureMachine,
    _ input: GestureInput,
    _ expectedEvent: GestureEvent?,
    _ expectedPhase: HotkeyGestureMachine.Phase,
  ) {
    var machine = makeMachine()
    #expect(machine.receive(input) == expectedEvent)
    #expect(machine.phase == expectedPhase)
  }

  private func idle() -> HotkeyGestureMachine {
    HotkeyGestureMachine()
  }

  private func holding() -> HotkeyGestureMachine {
    var machine = HotkeyGestureMachine()
    _ = machine.receive(.activation(at: .zero))
    return machine
  }

  private func provisional() -> HotkeyGestureMachine {
    var machine = holding()
    _ = machine.receive(.release(at: .milliseconds(100)))
    return machine
  }

  private func secondPress() -> HotkeyGestureMachine {
    var machine = provisional()
    _ = machine.receive(.activation(at: .milliseconds(200)))
    return machine
  }

  private func latched() -> HotkeyGestureMachine {
    var machine = secondPress()
    _ = machine.receive(.release(at: .milliseconds(300)))
    return machine
  }

  private func cleanupPending() -> HotkeyGestureMachine {
    var machine = HotkeyGestureMachine()
    _ = machine.receive(.cleanupStarted)
    return machine
  }

  private func blocked() -> HotkeyGestureMachine {
    var machine = HotkeyGestureMachine()
    _ = machine.receive(.escape)
    return machine
  }
}
