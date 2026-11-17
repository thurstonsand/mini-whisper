import AudioCapture
import Foundation

// MARK: - AudioVaultError

public enum AudioVaultError: Error, Equatable {
  case unreadableAudioFile(URL)
}

// MARK: - AudioVault

/// The media half of history: a flat directory of canonical WAVs, and the screenshots Expanded
/// context took beside them, named by entry id, so each has exactly one identity — the entry's.
/// The log references them by presence of `audio` and `screenshot` metadata, which is why
/// `reconcile` exists: at launch it forces the log and the disk back into agreement in whichever
/// direction they disagree.
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

  public func screenshotURL(id: UUID) -> URL {
    directoryURL.appendingPathComponent("\(id.uuidString).jpg")
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

  /// Writes the screenshot's JPEG and returns the metadata the entry should carry.
  public func writeScreenshot(
    _ jpeg: Data, id: UUID, shownToCleanup: Bool,
  ) throws -> ScreenshotMetadata {
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    try jpeg.write(to: screenshotURL(id: id), options: .atomic)
    return ScreenshotMetadata(byteCount: jpeg.count, shownToCleanup: shownToCleanup)
  }

  public func readScreenshot(id: UUID) throws -> Data {
    try Data(contentsOf: screenshotURL(id: id))
  }

  /// Reads back an entry's canonical WAV, for re-transcription and playback.
  public func read(id: UUID) throws -> CanonicalRecording {
    try CanonicalWAVReader.read(contentsOf: url(id: id))
  }

  /// Deletes the entries' audio and screenshot files. A file already gone is accepted — deletion
  /// is satisfied by absence — but any other failure propagates: reporting success after failing
  /// to delete data is how a retention promise turns into a lie.
  public func delete(_ ids: [UUID]) throws {
    for file in ids.flatMap({ [url(id: $0), screenshotURL(id: $0)] }) {
      do {
        try FileManager.default.removeItem(at: file)
      } catch CocoaError.fileNoSuchFile {
        continue
      }
    }
  }

  /// Returns the log corrected against the disk: entries whose WAV or JPEG is missing lose that
  /// file's metadata, and files no entry references — including ones not named by an entry UUID
  /// — are deleted.
  public func reconcile(_ log: HistoryLog) throws -> HistoryLog {
    var log = log
    var referencedFilenames = Set<String>()
    for index in log.entries.indices {
      let id = log.entries[index].id
      if log.entries[index].audio != nil {
        if FileManager.default.fileExists(atPath: url(id: id).path) {
          referencedFilenames.insert(url(id: id).lastPathComponent)
        } else {
          log.entries[index].audio = nil
        }
      }
      if log.entries[index].screenshot != nil {
        if FileManager.default.fileExists(atPath: screenshotURL(id: id).path) {
          referencedFilenames.insert(screenshotURL(id: id).lastPathComponent)
        } else {
          log.entries[index].screenshot = nil
        }
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
