import AudioCapture
import ComposableArchitecture
import Foundation
import History
import OSLog

// MARK: - History state

extension AppFeature {
  struct PendingDictation: Equatable {
    var generation: Int
    var recording: CanonicalRecording
    var createdAt: Date
    var engine: String
    var original: History.Transcription?
    var isFinishing = false
  }

  enum HistoryMaintenanceRequest: Equatable {
    case currentPolicy
    case policy(RetentionPolicy)

    // MARK: Internal

    var policy: RetentionPolicy? {
      switch self {
      case .currentPolicy:
        nil
      case let .policy(policy):
        policy
      }
    }
  }

  enum HistoryMaintenanceState: Equatable {
    case idle
    case running(HistoryMaintenanceRequest)
    case waiting(HistoryMaintenanceRequest)
  }

  func finishDeliveredDictation(
    _ state: inout State, result: DeliveryResult, method: Delivery.Method, detail: String?,
  ) -> Effect<Action> {
    finishDictation(
      &state, targetApp: result.targetApp,
      delivery: Delivery(text: result.text, method: method, detail: detail),
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
    let terminal = pending
    let id = uuid()
    let generation = terminal.generation
    let storesAudio = state.storesAudio
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
            await send(.historyEntryAbandoned(generation))
            return
          }
          audio = nil
        }
      }
      let entry = HistoryEntry(
        id: id, createdAt: terminal.createdAt, targetApp: targetApp,
        original: terminal.original, delivery: delivery, audio: audio,
      )
      await send(.historyEntryPrepared(generation, entry))
    }
  }

  func startDeferredHistoryMaintenance(_ state: inout State) -> Effect<Action> {
    guard case let .waiting(request) = state.historyMaintenance else {
      return .none
    }
    state.historyMaintenance = .running(request)
    return historyMaintenanceEffect(log: state.history, policy: request.policy, now: now)
  }

  func historyMaintenanceEffect(
    log: HistoryLog, policy requestedPolicy: RetentionPolicy?, now: Date,
  ) -> Effect<Action> {
    .run { send in
      do {
        let policy: RetentionPolicy =
          if let requestedPolicy {
            requestedPolicy
          } else {
            try await historyClient.loadRetentionPolicy()
          }
        let reconciled = try await historyClient.reconcile(log)
        try Task.checkCancellation()
        let outcome = Retention.apply(policy, to: reconciled, now: now)
        try await historyClient.deleteAudio(outcome.audioToDelete)
        try Task.checkCancellation()
        await send(.historyMaintenanceCompleted(outcome.log, policy))
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
