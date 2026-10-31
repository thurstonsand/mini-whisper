import AppSettings
import ComposableArchitecture
import FieldContext
import Foundation
import History
import HotkeyListener
import TranscriptCleanup

// MARK: - The delivery vertical

/// Capture, cleanup, paste. A dictation walks the three legs one at a time, because between them
/// it has a pill to move and an activation press to answer; a recovery walks none of them and
/// simply pastes.
extension AppFeature {
  enum DeliveryAttempt {
    case delivered(DeliveryOutcome)
    case failed(String)
  }

  /// The press is the only moment that names where the user meant the words to go, so the target
  /// is captured beside it — before the user has had a chance to look anywhere else.
  func captureTargetEffect(generation: Int) -> Effect<Action> {
    .run { send in await send(.targetCaptured(generation, deliveryTarget.capture())) }
  }

  /// The field's text is read as late as it can be, because it is the one fact the user keeps
  /// changing: during transcription they can type or move the caret. It is read from the target,
  /// so it is the field the dictation will land in, wherever the user is now. A target that has
  /// not arrived by the time the transcript has is captured here instead.
  func captureContextEffect(generation: Int, target: DeliveryTarget?) -> Effect<Action> {
    .run { send in
      let target =
        if let target {
          target
        } else {
          await deliveryTarget.capture()
        }
      let capture = await contextCapture.capture(target)
      await send(.contextCaptured(generation, capture, target))
    }.cancellable(id: CancelID.delivery(generation), cancelInFlight: true)
  }

  /// Paste-last has no dictation behind it and nothing to polish in text that was already
  /// delivered once, so it captures and pastes in one effect rather than walking the legs.
  func recoveryDeliveryEffect(transcript: String) -> Effect<Action> {
    .run { send in
      let target = await deliveryTarget.capture()
      let capture = await contextCapture.capture(target)
      guard !Task.isCancelled else {
        return
      }
      await deliver(
        transcript, capture: capture, target: target, submits: false, to: nil, send: send,
      )
    }.cancellable(id: CancelID.recoveryDelivery, cancelInFlight: true)
  }

  /// The pipeline's cleanup leg. The pill flips to Polishing only once there is a request in
  /// flight, so a configuration that turns out to be keyless never flashes a phase that is not
  /// happening, and any activation press cancels the request and delivers the transcript as heard.
  func cleanupEffect(
    generation: Int, transcript: String, conditioning: CleanupConditioning, target: CleanupTarget,
  ) -> Effect<Action> {
    .run { send in
      let resolution = await TranscriptPipeline().resolveCleanup(
        transcript, conditioning: conditioning, target: target,
        requestStarting: { configuration in
          await send(.cleanupStarted(generation, configuration))
        },
      )
      // A skip cancelled this request and resolved the delivery itself, so it is owed nothing.
      guard let resolution else {
        return
      }
      await send(.cleanupResolved(generation, resolution))
    }.cancellable(id: CancelID.cleanup(generation), cancelInFlight: true)
  }

  /// Starts every delivery whose turn has come. A dictation waits while an earlier one bound for
  /// the same target has not landed, so one target hears its dictations in the order they were
  /// spoken; and only one GUI delivery runs at a time, because each borrows the clipboard and may
  /// borrow focus.
  func deliverReadyDictations(_ state: inout State) -> Effect<Action> {
    let dictations = (Array(state.backgroundDictations.values) + [state.pendingDictation])
      .compactMap(\.self)
      .sorted { $0.generation < $1.generation }
    var guiDeliveryRunning = dictations.contains {
      $0.isDelivering && !$0.isFinishing && $0.target?.pane == nil
    }
    var effects: [Effect<Action>] = []
    for (index, dictation) in dictations.enumerated() {
      guard let text = dictation.readyText, !dictation.isDelivering,
            let capture = dictation.capture, let target = dictation.target
      else {
        continue
      }
      let waitsOnEarlier = dictations[..<index].contains { earlier in
        !earlier.isFinishing && earlier.target?.isSameDestination(as: target) == true
      }
      guard !waitsOnEarlier, target.pane != nil || !guiDeliveryRunning else {
        continue
      }
      if target.pane == nil {
        guiDeliveryRunning = true
      }
      var started = dictation
      started.isDelivering = true
      state.updateDictation(started)
      effects.append(
        .run { send in
          await deliver(
            text, capture: capture, target: target, submits: dictation.submits,
            to: dictation.generation, send: send,
          )
        }.cancellable(id: CancelID.delivery(dictation.generation), cancelInFlight: true),
      )
    }
    return .merge(effects)
  }

  // MARK: Private

  /// A dictation answers to its generation; a recovery answers to nobody.
  private func deliver(
    _ text: String, capture: ContextCapture, target: DeliveryTarget, submits: Bool,
    to generation: Int?, send: Send<Action>,
  ) async {
    let adjusted = capture.adjusted(text)
    guard !Task.isCancelled else {
      return
    }
    let attempt: DeliveryAttempt
    do {
      if let noReceiver = capture.noReceiverReason {
        attempt = .delivered(.noReceiver(noReceiver))
      } else {
        attempt = try await .delivered(delivery.deliver(adjusted, target, submits))
      }
    } catch {
      attempt = .failed(error.localizedDescription)
    }
    switch attempt {
    case let .delivered(outcome):
      let result = DeliveryResult(text: adjusted, targetApp: target.app, outcome: outcome)
      await send(
        generation.map { .deliveryCompleted($0, result) } ?? .recoveryDeliveryCompleted(result),
      )
    case let .failed(message):
      let failure = DeliveryFailure(text: adjusted, targetApp: target.app, message: message)
      await send(
        generation.map { .deliveryFailed($0, failure) } ?? .recoveryDeliveryFailed(failure),
      )
    }
  }
}

// MARK: - What a capture answers for

extension ContextCapture {
  var focusedTextContext: FocusedTextContext? {
    guard case let .available(context) = self else {
      return nil
    }
    return context
  }

  var noReceiverReason: NoReceiverReason? {
    switch self {
    case .unavailable(.noFocusedElement):
      .noFocusedElement
    case let .unavailable(.nonTextElement(role)):
      .nonTextElement(role: role)
    case .available,
         .unavailable:
      nil
    }
  }
}
