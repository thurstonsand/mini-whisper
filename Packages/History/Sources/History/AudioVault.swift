import AudioCapture
import Foundation

// MARK: - AudioVaultError

public enum AudioVaultError: Error, Equatable {
  case unreadableAudioFile(URL)
}

// MARK: - AudioVault

/// The audio half of history: a flat directory of canonical WAVs named by entry id, so audio has
/// exactly one identity — the entry's. The log references it by presence of `audio` metadata,
/// which is why `reconcile` exists: at launch it forces the log and the disk back into agreement
/// in whichever direction they disagree.
public struct AudioVault: Sendable {
  // MARK: Lifecycle

  public init(directoryURL: URL) {
    self.directoryURL = directoryURL
  }

  // MARK: Public

  public let directoryURL: URL

  public func url(id: UUID) -> URL {
    directoryURL.appendingPathComponent("\(id.uuidString).wav")
  }

  /// Writes the recording's canonical WAV and returns the metadata the entry should carry.
  public func write(_ recording: CanonicalRecording, id: UUID) throws -> AudioMetadata {
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let url = url(id: id)
    try CanonicalWAVWriter.write(recording, to: url)
    guard let byteCount = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
      throw AudioVaultError.unreadableAudioFile(url)
    }
    return AudioMetadata(durationSeconds: recording.durationSeconds, byteCount: byteCount)
  }

  /// Reads back an entry's canonical WAV, for re-transcription and playback.
  public func read(id: UUID) throws -> CanonicalRecording {
    try CanonicalWAVReader.read(contentsOf: url(id: id))
  }

  /// Deletes the entries' audio files. A file already gone is accepted — deletion is satisfied
  /// by absence — but any other failure propagates: reporting success after failing to delete
  /// data is how a retention promise turns into a lie.
  public func delete(_ ids: [UUID]) throws {
    for id in ids {
      do {
        try FileManager.default.removeItem(at: url(id: id))
      } catch CocoaError.fileNoSuchFile {
        continue
      }
    }
  }

  /// Returns the log corrected against the disk: entries whose WAV is missing lose their audio
  /// metadata, and files no entry references — including ones not named by an entry UUID —
  /// are deleted.
  public func reconcile(_ log: HistoryLog) throws -> HistoryLog {
    var log = log
    var referencedFilenames = Set<String>()
    for index in log.entries.indices where log.entries[index].audio != nil {
      let audioURL = url(id: log.entries[index].id)
      if FileManager.default.fileExists(atPath: audioURL.path) {
        referencedFilenames.insert(audioURL.lastPathComponent)
      } else {
        log.entries[index].audio = nil
      }
    }

    guard FileManager.default.fileExists(atPath: directoryURL.path) else {
      return log
    }
    let files = try FileManager.default.contentsOfDirectory(
      at: directoryURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles],
    )
    for file in files where !referencedFilenames.contains(file.lastPathComponent) {
      try FileManager.default.removeItem(at: file)
    }
    return log
  }
}
