import Foundation
@testable import HotkeyListener
import Testing

struct SubmitKeyGateTests {
  @Test func `an owed dictation claims Return only while the user is at its target`() {
    let gate = SubmitKeyGate()
    #expect(!gate.claimsReturn())

    gate.isAtOwedTarget = { true }
    #expect(gate.claimsReturn())
    gate.isAtOwedTarget = { false }
    #expect(!gate.claimsReturn())

    // A live recording owns every Return, wherever the user is.
    gate.isArmed = true
    #expect(gate.claimsReturn())
  }

  @Test func `a check that overruns its deadline leaves Return to the field`() {
    let gate = SubmitKeyGate()
    gate.isAtOwedTarget = {
      Thread.sleep(forTimeInterval: 0.2)
      return true
    }

    #expect(!gate.claimsReturn(deadline: .milliseconds(20)))
    #expect(gate.claimsReturn(deadline: .seconds(1)))
  }
}
