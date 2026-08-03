import Foundation
@testable import HotkeyListener
import Testing

struct InteractionPerformanceBenchmarkTests {
  @Test func `one hundred thousand hold transitions stay within budget`() {
    var machine = HotkeyGestureMachine()
    var emittedEvents = 0
    let clock = ContinuousClock()
    let startedAt = clock.now

    for index in 0 ..< 100_000 {
      let activation = Duration.seconds(index)
      if machine.receive(.activation(at: activation)) != nil {
        emittedEvents += 1
      }
      if machine.receive(.release(at: activation + .milliseconds(500))) != nil {
        emittedEvents += 1
      }
    }

    let elapsed = startedAt.duration(to: clock.now)
    #expect(emittedEvents == 200_000)
    #expect(elapsed < .milliseconds(100))
  }
}
