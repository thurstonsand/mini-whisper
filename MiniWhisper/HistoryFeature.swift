import ASREngine
import ComposableArchitecture
import Foundation
import History
import OSLog
import SpeechDictionary
import SwiftUI
import TranscriptCleanup

// MARK: - HistoryFeature

@Reducer struct HistoryFeature {
  // MARK: Internal

  enum CursorMovement: Equatable {
    case previous
    case next
  }

  struct PendingRetentionReduction: Equatable {
    var field: RetentionPolicy.Key
    var value: RetentionTTL
  }

  @ObservableState struct State: Equatable {
    // MARK: Lifecycle

    init(
      log: Shared<HistoryLog>, retention: Shared<RetentionPolicy>,
      dictionary: Shared<DictionaryContents>,
      improveRecognition: Shared<Bool>,
      cleanup: Shared<CleanupSettings>,
    ) {
      _log = log
      _retention = retention
      _dictionary = dictionary
      _improveRecognition = improveRecognition
      _cleanup = cleanup
    }

    // MARK: Internal

    @Shared var log: HistoryLog
    @Shared var dictionary: DictionaryContents
    @Shared var improveRecognition: Bool
    /// A re-transcription is a dictation minus the delivery, so it polishes under whatever the
    /// pane says right now — not under whatever governed the dictation months ago.
    @Shared var cleanup: CleanupSettings
    var search = ""
    var cursor: UUID?
    var copiedEntryID: UUID?
    /// ⌥ held: every row with a transcript under its text shows it, and copying takes it.
    var isRevealingRawText = false
    var playingEntryID: UUID?
    var retranscribingEntryIDs: Set<UUID> = []
    var retranscriptionFailures: [UUID: String] = [:]
    @Shared var retention: RetentionPolicy
    var pendingRetentionReduction: PendingRetentionReduction?
    var isStoragePresented = false

    var filteredEntries: [HistoryEntry] {
      let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !query.isEmpty else {
        return log.entries
      }
      return log.entries.filter {
        $0.displayText?.localizedCaseInsensitiveContains(query) == true
      }
    }

    /// The row the cursor is on. A pane with rows always has a place, so an unmoved cursor is the
    /// first row rather than nowhere: entering the column highlights something, and copying it
    /// copies that.
    var cursorEntry: HistoryEntry? {
      let entries = filteredEntries
      return entries.first { $0.id == cursor } ?? entries.first
    }

    /// Moves the cursor off `id` before it disappears: to the row that takes its place, or to the
    /// one above when it was last. A cursor that is already elsewhere stays where it is.
    mutating func advanceCursor(past id: UUID) {
      guard cursorEntry?.id == id else {
        return
      }
      let entries = filteredEntries
      guard let index = entries.firstIndex(where: { $0.id == id }) else {
        cursor = nil
        return
      }
      let survivors = entries.filter { $0.id != id }
      cursor = survivors.isEmpty ? nil : survivors[min(index, survivors.count - 1)].id
    }
  }

  enum Action: Equatable {
    case searchChanged(String)
    case cursorMoved(CursorMovement)
    case cursorHovered(UUID)
    case copyRequested
    case rowTapped(UUID)
    case revealChanged(Bool)
    case copyFailed(String)
    case copyFinished(UUID)
    case playTapped(UUID)
    case playbackEnded(UUID)
    case playbackFailed(UUID, String)
    case deleteTapped(UUID)
    case deleteCompleted(UUID)
    case deleteFailed(UUID, String)
    case retranscribeTapped(UUID)
    case retranscriptionCompleted(UUID, ProcessedTranscript)
    case retranscriptionFailed(UUID, String)
    case storagePresentationChanged(Bool)
    case retentionProposed(RetentionPolicy.Key, RetentionTTL)
    case retentionReductionCancelled
    case retentionReductionConfirmed
    case delegate(Delegate)

    // MARK: Internal

    enum Delegate: Equatable {
      case retentionChanged
    }
  }

  enum CancelID: Hashable {
    case copy(UUID)
  }

  @Dependency(\.asrEngine) var asrEngine
  @Dependency(\.continuousClock) var clock
  @Dependency(\.date.now) var now
  @Dependency(\.delivery) var delivery
  @Dependency(\.historyClient) var historyClient
  @Dependency(\.historyPlayback) var playback

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case let .searchChanged(search):
        state.search = search
        return .none
      case let .cursorMoved(movement):
        let entries = state.filteredEntries
        guard let place = state.cursorEntry,
              let current = entries.firstIndex(where: { $0.id == place.id })
        else {
          return .none
        }
        let offset = movement == .next ? 1 : -1
        state.cursor = entries[min(max(current + offset, 0), entries.count - 1)].id
        return .none
      case let .cursorHovered(id):
        guard state.filteredEntries.contains(where: { $0.id == id }) else {
          return .none
        }
        state.cursor = id
        return .none
      case .copyRequested:
        guard let place = state.cursorEntry else {
          return .none
        }
        state.cursor = place.id
        return copy(place.id, state: &state)
      case let .rowTapped(id):
        state.cursor = id
        return copy(id, state: &state)
      // The peek is the whole pane's, not one row's: every transcript a cleanup pass rewrote
      // comes back for as long as the key is down.
      case let .revealChanged(isRevealing):
        state.isRevealingRawText = isRevealing
        return .none
      case let .copyFailed(message):
        historyLogger.error("History copy failed: \(message, privacy: .public)")
        return .none
      case let .copyFinished(id):
        guard state.copiedEntryID == id else {
          return .none
        }
        state.copiedEntryID = nil
        return .none
      case let .playTapped(id):
        guard state.log.entries.first(where: { $0.id == id })?.audio != nil else {
          return .none
        }
        guard state.playingEntryID != id else {
          state.playingEntryID = nil
          return .run { _ in await playback.stop() }
        }
        state.playingEntryID = id
        return .run { send in
          if try await playback.play(id) == .finished {
            await send(.playbackEnded(id))
          }
        } catch: { error, send in
          await send(.playbackFailed(id, error.localizedDescription))
        }
      case let .playbackEnded(id):
        guard state.playingEntryID == id else {
          return .none
        }
        state.playingEntryID = nil
        return .none
      case let .playbackFailed(id, message):
        if state.playingEntryID == id {
          state.playingEntryID = nil
        }
        historyLogger.error("History playback failed: \(message, privacy: .public)")
        return .none
      case let .deleteTapped(id):
        guard state.log.entries.contains(where: { $0.id == id }) else {
          return .none
        }
        return .run { send in
          do {
            try await historyClient.deleteAudio([id])
            await send(.deleteCompleted(id))
          } catch { await send(.deleteFailed(id, error.localizedDescription)) }
        }
      case let .deleteCompleted(id):
        state.advanceCursor(past: id)
        state.$log.withLock { $0.entries.removeAll { $0.id == id } }
        guard state.playingEntryID == id else {
          return save(state.$log)
        }
        state.playingEntryID = nil
        return .merge(save(state.$log), .run { _ in await playback.stop() })
      case let .deleteFailed(_, message):
        historyLogger.error("History deletion failed: \(message, privacy: .public)")
        return .none
      // A re-run is the same processing a dictation gets — the engine, then the cleanup pass —
      // conditioned by the facts the entry kept: the field the words were meant for and the
      // application they were bound for, against today's vocabulary and today's pane.
      case let .retranscribeTapped(id):
        guard let entry = state.log.entries.first(where: { $0.id == id }), entry.audio != nil
        else {
          return .none
        }
        let dictionary = state.dictionary.transcriptionDictionary(
          boostsVocabulary: state.improveRecognition,
        )
        let conditioning = CleanupConditioning(
          fieldContext: entry.fieldContext,
          vocabulary: state.dictionary.vocabulary.map(\.text),
          targetBundleID: entry.targetApp?.bundleID,
        )
        let cleanup = state.cleanup
        state.retranscribingEntryIDs.insert(id)
        state.retranscriptionFailures[id] = nil
        return .run { send in
          do {
            let recording = try await historyClient.loadAudio(id)
            let processed = try await TranscriptPipeline().process(
              recording, dictionary: dictionary, conditioning: conditioning, settings: cleanup,
            )
            await send(.retranscriptionCompleted(id, processed))
          } catch { await send(.retranscriptionFailed(id, error.localizedDescription)) }
        }
      case let .retranscriptionCompleted(id, processed):
        state.retranscribingEntryIDs.remove(id)
        guard case let .transcript(text) = processed.outcome,
              let index = state.log.entries.firstIndex(where: { $0.id == id })
        else {
          let message =
            switch processed.outcome {
            case .tooShort:
              "The recording is too short to transcribe."
            case .noSpeech:
              "No speech was recognized."
            case .engineEmpty:
              "The speech engine returned an empty transcript."
            case .transcript:
              preconditionFailure()
            }
          state.retranscriptionFailures[id] = message
          historyLogger.error("History re-transcription failed: \(message, privacy: .public)")
          return .none
        }
        state.$log.withLock {
          $0.entries[index].addRetranscription(
            Transcription(
              text: text, engine: asrEngine.identity(), transcribedAt: now,
              cleanup: processed.cleanup,
            ),
          )
        }
        return save(state.$log)
      case let .retranscriptionFailed(id, message):
        state.retranscribingEntryIDs.remove(id)
        state.retranscriptionFailures[id] = message
        historyLogger.error("History re-transcription failed: \(message, privacy: .public)")
        return .none
      case let .storagePresentationChanged(presented):
        state.isStoragePresented = presented
        return .none
      case let .retentionProposed(field, value):
        guard value >= state.retention[field] else {
          state.pendingRetentionReduction = PendingRetentionReduction(field: field, value: value)
          return .none
        }
        return applyRetention(field: field, value: value, state: &state)
      case .retentionReductionCancelled:
        state.pendingRetentionReduction = nil
        return .none
      case .retentionReductionConfirmed:
        guard let pending = state.pendingRetentionReduction else {
          return .none
        }
        state.pendingRetentionReduction = nil
        return applyRetention(field: pending.field, value: pending.value, state: &state)
      case .delegate:
        return .none
      }
    }
  }

  // MARK: Private

  /// A copy takes what the row is showing, which is what the peek changes: ⌥ held copies the
  /// transcript, exactly as the row reads under the same key.
  private func copy(_ id: UUID, state: inout State) -> Effect<Action> {
    guard let entry = state.log.entries.first(where: { $0.id == id }),
          let text = state.isRevealingRawText
          ? entry.revealedText ?? entry.displayText
          : entry.displayText
    else {
      return .none
    }
    state.copiedEntryID = id
    return .merge(
      .run { send in
        do { try await delivery.copy(text) } catch {
          await send(.copyFailed(error.localizedDescription))
        }
      },
      .run { send in
        try await clock.sleep(for: .seconds(1.2))
        await send(.copyFinished(id))
      }.cancellable(id: CancelID.copy(id), cancelInFlight: true),
    )
  }

  /// Writing the shared policy persists it; the delegate only asks the app to act on it, because
  /// a shortened limit has to prune what now falls outside it before the pane can claim it did.
  private func applyRetention(
    field: RetentionPolicy.Key, value: RetentionTTL, state: inout State,
  ) -> Effect<Action> {
    state.$retention.withLock { $0[field] = value }
    return .send(.delegate(.retentionChanged))
  }

  private func save(_ log: Shared<HistoryLog>) -> Effect<Action> {
    .run { _ in
      do { try await log.save() } catch {
        historyLogger
          .error("History failed to persist: \(error.localizedDescription, privacy: .public)")
      }
    }
  }
}
