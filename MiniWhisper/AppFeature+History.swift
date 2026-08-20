import AppSettings
import AudioCapture
import ComposableArchitecture
import FieldContext
import Foundation
import History
import OSLog
import TranscriptCleanup

// MARK: - History state

extension AppFeature {
  /// One dictation in flight, whole: the audio it captured, what the engine made of it, the
  /// field it is bound for, and what the cleanup pass did. Every leg of the vertical reads and
  /// writes this one record, so no fact about a dictation has a second home to drift from.
  struct PendingDictation: Equatable {
    var generation: Int
    var recording: CanonicalRecording
    var createdAt: Date
    var engine: String
    /// What the engine said, and only that. Cleanup's rewrite is kept apart in `cleanupRecord`
    /// and joined to the transcription when the entry is written.
    var original: History.Transcription?
    /// The focused field as it was immediately before the paste — one snapshot, which conditions
    /// the cleanup prompt and then adjusts the joined text.
    var capture: ContextCapture?
    var targetApp: TargetApp?
    /// The configuration a request actually went out with, so a pane edit mid-flight cannot
    /// rewrite history — and so that a non-nil value means a request is genuinely in flight.
    var cleanup: CleanupConfiguration?
    var cleanupStartedAt: Date?
    var cleanupRecord: CleanupRecord?
    var isFinishing = false

    var fieldContext: FocusedTextContext? {
      capture?.focusedTextContext
    }

    /// What the pill owes the user once this dictation's paste lands, beyond the paste itself. A
    /// cleanup that could not run is the more specific degradation, so it outranks the
    /// missing-context notice when one dictation managed both.
    var deliveredNotice: PillFeature.Action {
      if case .failed = cleanupRecord?.disposition {
        .cleanupUnavailable
      } else if case .unavailable = capture {
        .fieldContextUnavailable
      } else {
        .dismiss
      }
    }

    /// How long the user waited on the endpoint before a press or an Escape ended the wait.
    func elapsedCleanup(_ now: Date) -> Double {
      cleanupStartedAt.map { now.timeIntervalSince($0) } ?? 0
    }
  }

  enum HistoryMaintenanceState: Equatable {
    case idle
    case running
    case waiting
  }

  func finishDeliveredDictation(_ state: inout State, result: DeliveryResult) -> Effect<Action> {
    finishDictation(
      &state, targetApp: result.targetApp, delivery: result.outcome.delivery(of: result.text),
    )
  }

  func finishDictation(
    _ state: inout State, targetApp: TargetApp? = nil, delivery: Delivery?,
  ) -> Effect<Action> {
    guard var pending = state.pendingDictation, !pending.isFinishing else {
      return .none
    }
    guard pending.original != nil || state.storesAudio else {
      state.pendingDictation = nil
      state.dictationInFlight = false
      return .none
    }
    pending.isFinishing = true
    state.pendingDictation = pending
    let generation = pending.generation
    return archiveEffect(
      pending, targetApp: targetApp, delivery: delivery, storesAudio: state.storesAudio,
    ) { entry in
      entry.map { .historyEntryPrepared(generation, $0) } ?? .historyEntryAbandoned(generation)
    }
  }

  /// A skipped dictation's terminal write. It answers to no generation and holds no place in the
  /// store beyond `skippedDictations`, so it leaves as it is archived.
  func archiveSkippedDictation(
    _ generation: Int, state: inout State, delivery: Delivery?,
  ) -> Effect<Action> {
    guard let skipped = state.skippedDictations.removeValue(forKey: generation) else {
      return .none
    }
    return archiveEffect(
      skipped, targetApp: skipped.targetApp, delivery: delivery, storesAudio: state.storesAudio,
    ) { .skippedDictationArchived($0) }
  }

  /// One dictation's terminal write: the audio if it is kept, then the entry. A nil entry means
  /// the dictation left nothing durable behind and the caller should forget it.
  private func archiveEffect(
    _ terminal: PendingDictation, targetApp: TargetApp?, delivery: Delivery?, storesAudio: Bool,
    completion: @escaping @Sendable (HistoryEntry?) -> Action,
  ) -> Effect<Action> {
    let id = uuid()
    return .run { send in
      let audio: AudioMetadata?
      if !storesAudio {
        audio = nil
      } else {
        do {
          audio = try await historyClient.writeAudio(terminal.recording, id)
        } catch {
          historyLogger.error(
            "History audio write failed: \(error.localizedDescription, privacy: .public)",
          )
          guard terminal.original != nil else {
            await send(completion(nil))
            return
          }
          audio = nil
        }
      }
      // Cleanup's record joins the transcription it polished only here, at the write: in flight
      // the two are separate facts about the dictation, and the entry is where they meet.
      var original = terminal.original
      original?.cleanup = terminal.cleanupRecord
      let entry = HistoryEntry(
        id: id, createdAt: terminal.createdAt, targetApp: targetApp,
        original: original, fieldContext: terminal.fieldContext,
        delivery: delivery, audio: audio,
      )
      await send(completion(entry))
    }
  }

  func startDeferredHistoryMaintenance(_ state: inout State) -> Effect<Action> {
    guard state.historyMaintenance == .waiting else {
      return .none
    }
    state.historyMaintenance = .running
    return historyMaintenanceEffect(log: state.history, policy: state.settings.retention, now: now)
  }

  func historyMaintenanceEffect(
    log: HistoryLog, policy: RetentionPolicy, now: Date,
  ) -> Effect<Action> {
    .run { send in
      do {
        let reconciled = try await historyClient.reconcile(log)
        try Task.checkCancellation()
        let outcome = Retention.apply(policy, to: reconciled, now: now)
        try await historyClient.deleteAudio(outcome.audioToDelete)
        try Task.checkCancellation()
        await send(.historyMaintenanceCompleted(outcome.log))
      } catch is CancellationError {
        return
      } catch {
        await send(.historyMaintenanceFailed(error.localizedDescription))
      }
    }.cancellable(id: CancelID.historyMaintenance, cancelInFlight: true)
  }

  func deleteHistoryAudio(_ ids: [UUID]) -> Effect<Action> {
    .run { send in
      do {
        try await historyClient.deleteAudio(ids)
      } catch {
        await send(
          .historyPersistenceFailed("History audio cleanup failed: \(error.localizedDescription)"),
        )
      }
    }
  }

  func saveHistory(_ history: Shared<HistoryLog>) -> Effect<Action> {
    .run { send in
      do {
        try await history.save()
      } catch {
        await send(.historyPersistenceFailed(error.localizedDescription))
      }
    }
  }
}

// MARK: - History details

extension CleanupRecord {
  /// The record a resolution leaves behind. A pass-through leaves none: nothing was attempted, so
  /// there is nothing to attribute.
  init?(_ resolution: CleanupResolution) {
    guard case let .attempted(configuration, attempt) = resolution else {
      return nil
    }
    let disposition: CleanupDisposition
    let seconds: Double
    switch attempt {
    case let .cleaned(text, elapsed):
      disposition = .cleaned(text)
      seconds = elapsed
    case let .skipped(elapsed):
      disposition = .skipped
      seconds = elapsed
    case let .failed(reason, elapsed):
      disposition = .failed(reason)
      seconds = elapsed
    }
    self.init(
      disposition: disposition, model: configuration.model, endpoint: configuration.endpoint,
      durationSeconds: seconds,
    )
  }
}

extension DeliveryOutcome {
  func delivery(of text: String) -> Delivery {
    switch self {
    case let .pasted(restoration):
      Delivery(text: text, method: .pasted, detail: restoration.historyDetail)
    case let .copied(fallback):
      Delivery(text: text, method: .copied, detail: fallback.historyDetail)
    case let .noReceiver(reason):
      Delivery(text: text, method: .noReceiver, detail: reason.historyDetail)
    }
  }
}

extension CleanupFailure {
  var historyDetail: String {
    switch self {
    case .unreachable:
      "unreachable"
    case let .httpStatus(code, _):
      "httpStatus \(code)"
    case let .timedOut(timeout):
      "timedOut \(Int(timeout.rounded()))s"
    case .malformedResponse:
      "malformedResponse"
    case .degenerateResponse:
      "degenerateResponse"
    }
  }
}

extension ClipboardRestoration {
  var historyDetail: String? {
    switch self {
    case .restored:
      nil
    case .skipped:
      "clipboardChanged"
    case .failed:
      "clipboardRestoreFailed"
    }
  }
}

extension DeliveryFallback {
  var historyDetail: String {
    switch self {
    case .accessibilityPermissionMissing:
      "accessibilityPermissionMissing"
    case .secureInput:
      "secureInput"
    case .eventCreationFailed:
      "eventCreationFailed"
    }
  }
}

extension NoReceiverReason {
  var historyDetail: String {
    switch self {
    case .noFocusedElement:
      "noFocusedElement"
    case let .nonTextElement(role):
      if let role {
        "nonTextElement role=\(role)"
      } else {
        "nonTextElement"
      }
    }
  }
}
