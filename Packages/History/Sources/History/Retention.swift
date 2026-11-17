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
  /// Entries whose stored audio and screenshot the caller must delete — the log no longer
  /// references them.
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
      let age = now.timeIntervalSince(entry.createdAt)
      // A screenshot is a recording of the screen, kept beside the recording of the voice, and
      // the audio limit is the one that governs it.
      let storesMedia = entry.audio != nil || entry.screenshot != nil
      if let maxAge = policy.transcripts.maxAge, age >= maxAge {
        if storesMedia {
          audioToDelete.append(entry.id)
        }
        continue
      }
      var entry = entry
      if storesMedia, let maxAge = policy.audio.maxAge, age >= maxAge {
        audioToDelete.append(entry.id)
        entry.audio = nil
        entry.screenshot = nil
      }
      kept.append(entry)
    }

    var log = log
    log.entries = kept
    return RetentionOutcome(log: log, audioToDelete: audioToDelete)
  }
}
