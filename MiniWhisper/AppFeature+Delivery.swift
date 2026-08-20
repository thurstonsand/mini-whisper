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
  /// Where a finished paste reports. A dictation answers to the generation that owns it; a
  /// skipped tail answers to the generation it once was, which is deliberately no longer the
  /// current one; a recovery answers to nobody.
  enum DeliveryDestination: Equatable {
    case dictation(Int)
    case recovery
    case skipped(Int)

    // MARK: Internal

    /// A skipped tail gets an id of its own, so the next dictation cancelling the delivery id
    /// cannot cut short the very paste the user asked to keep — and so two of them can finish at
    /// once without either standing in the other's way.
    var cancelID: CancelID {
      switch self {
      case .dictation,
           .recovery:
        .delivery
      case let .skipped(generation):
        .skippedDelivery(generation)
      }
    }
  }

  enum DeliveryAttempt {
    case delivered(DeliveryOutcome)
    case failed(String)
  }

  /// The capture happens as late as it can, because it is the only moment whose answer is still
  /// true: during transcription the user can type, move the caret, or switch windows without ever
  /// leaving the application. It is a best-effort snapshot of the frontmost field rather than a
  /// guarantee — nothing stops a third application from taking the front before the synthetic ⌘V.
  func captureContextEffect(generation: Int) -> Effect<Action> {
    .run { send in
      let (capture, targetApp) = await captureFrontmostField()
      // A newer dictation has already claimed the field; this paste would land in it.
      guard !Task.isCancelled else {
        return
      }
      await send(.contextCaptured(generation, capture, targetApp))
    }.cancellable(id: CancelID.delivery, cancelInFlight: true)
  }

  /// Paste-last has no dictation behind it and nothing to polish in text that was already
  /// delivered once, so it captures and pastes in one effect rather than walking the legs.
  func recoveryDeliveryEffect(transcript: String) -> Effect<Action> {
    .run { send in
      let (capture, targetApp) = await captureFrontmostField()
      guard !Task.isCancelled else {
        return
      }
      await deliver(transcript, capture: capture, targetApp: targetApp, to: .recovery, send: send)
    }.cancellable(id: CancelID.delivery, cancelInFlight: true)
  }

  /// The pipeline's cleanup leg. The pill flips to Polishing only once there is a request in
  /// flight, so a configuration that turns out to be keyless never flashes a phase that is not
  /// happening, and any activation press cancels the request and delivers the transcript as heard.
  func cleanupEffect(
    generation: Int, skipComponents: [String], transcript: String,
    conditioning: CleanupConditioning, settings: CleanupSettings,
  ) -> Effect<Action> {
    .run { send in
      let resolution = await TranscriptPipeline().resolveCleanup(
        transcript, conditioning: conditioning, settings: settings,
        requestStarting: { configuration in
          await send(.cleanupStarted(generation, configuration))
          await send(.pill(.polishingStarted(skipComponents: skipComponents)))
          // The wait the activation key can resolve: the machine has to know it is happening
          // before the request does.
          await send(.hotkeyListenerEvent(.gestureInput(.cleanupStarted)))
        },
      )
      // A skip cancelled this request and resolved the delivery itself, so it is owed nothing.
      guard let resolution else {
        return
      }
      await send(.cleanupResolved(generation, resolution))
    }.cancellable(id: CancelID.cleanup, cancelInFlight: true)
  }

  func deliverEffect(
    to destination: DeliveryDestination, text: String, capture: ContextCapture,
    targetApp: TargetApp?,
  ) -> Effect<Action> {
    .run { send in
      await deliver(text, capture: capture, targetApp: targetApp, to: destination, send: send)
    }.cancellable(id: destination.cancelID, cancelInFlight: true)
  }

  // MARK: Private

  private func captureFrontmostField() async -> (ContextCapture, TargetApp?) {
    async let targetApplication = workspace.frontmostApplication()
    let capture = await contextCapture.capture(.delivery)
    let targetApp = await targetApplication.map {
      TargetApp(bundleID: $0.bundleID, name: $0.name)
    }
    return (capture, targetApp)
  }

  private func deliver(
    _ text: String, capture: ContextCapture, targetApp: TargetApp?,
    to destination: DeliveryDestination, send: Send<Action>,
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
        attempt = try await .delivered(delivery.deliver(adjusted))
      }
    } catch {
      attempt = .failed(error.localizedDescription)
    }
    switch attempt {
    case let .delivered(outcome):
      let result = DeliveryResult(text: adjusted, targetApp: targetApp, outcome: outcome)
      switch destination {
      case let .dictation(generation):
        await send(.deliveryCompleted(generation, result))
      case .recovery:
        await send(.recoveryDeliveryCompleted(result))
      case let .skipped(generation):
        await send(.skippedDeliveryCompleted(generation, result))
      }
    case let .failed(message):
      let failure = DeliveryFailure(text: adjusted, targetApp: targetApp, message: message)
      switch destination {
      case let .dictation(generation):
        await send(.deliveryFailed(generation, failure))
      case .recovery:
        await send(.recoveryDeliveryFailed(failure))
      case let .skipped(generation):
        await send(.skippedDeliveryFailed(generation, failure))
      }
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
