import Foundation

// MARK: - RetentionOutcome

public struct RetentionOutcome: Equatable, Sendable {
  // MARK: Lifecycle

  public init(log: HistoryLog, audioToDelete: [UUID]) {
    self.log = log
    self.audioToDelete = audioToDelete
  }

  // MARK: Public

  public let log: HistoryLog
  /// Entries whose stored audio the caller must delete — the log no longer references it.
  public let audioToDelete: [UUID]
}

// MARK: - Retention

/// Pure policy over the log. The caller owns the shared state and the disk: it replaces the log
/// with the returned one and deletes the returned entries' audio. Must run when a TTL setting
/// changes, not only on a timer, or the control appears to do nothing.
public enum Retention {
  public static func apply(
    _ policy: RetentionPolicy, to log: HistoryLog, now: Date = Date(),
  ) -> RetentionOutcome {
    var kept = [HistoryEntry]()
    var audioToDelete = [UUID]()

    for entry in log.entries {
      guard !entry.pinned else {
        kept.append(entry)
        continue
      }
      let age = now.timeIntervalSince(entry.createdAt)
      if let maxAge = policy.transcripts.maxAge, age >= maxAge {
        if entry.audio != nil {
          audioToDelete.append(entry.id)
        }
        continue
      }
      var entry = entry
      if entry.audio != nil, let maxAge = policy.audio.maxAge, age >= maxAge {
        audioToDelete.append(entry.id)
        entry.audio = nil
      }
      kept.append(entry)
    }

    var log = log
    log.entries = kept
    return RetentionOutcome(log: log, audioToDelete: audioToDelete)
  }
}
