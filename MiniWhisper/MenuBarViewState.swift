import ASREngine
import Foundation

struct MenuBarViewState: Equatable {
  // MARK: Internal

  let degradations: [Degradation]
  let engineReadiness: EngineReadiness
  let inputDeviceName: String?
  let canCopyLastTranscript: Bool

  var statusText: String {
    "\(readinessText) · \(inputDeviceName ?? "No input device")"
  }

  /// The status line reads as one sentence to a screen reader, where the interpuncts do not.
  var accessibilityStatusText: String {
    statusText.replacing(" · ", with: "; ")
  }

  // MARK: Private

  /// "Ready" is a claim about the whole app, so a menu cannot make it directly above a row asking
  /// for a permission. The engine names its own troubles, since only it has progress to report;
  /// anything else that stops a dictation simply withdraws the claim and lets the rows say why.
  private var readinessText: String {
    engineReadiness == .ready && !degradations.isEmpty ? "Not ready" : engineReadiness.statusText
  }
}
