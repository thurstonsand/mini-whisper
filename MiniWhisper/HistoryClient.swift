import AppSettings
import AudioCapture
import ComposableArchitecture
import Foundation
import History

// MARK: - HistoryClient

@DependencyClient struct HistoryClient {
  var loadRetentionPolicy: @Sendable () async throws -> RetentionPolicy
  var writeAudio: @Sendable (CanonicalRecording, UUID) async throws -> AudioMetadata
  var deleteAudio: @Sendable ([UUID]) async throws -> Void
  var reconcile: @Sendable (HistoryLog) async throws -> HistoryLog
}

// MARK: DependencyKey

extension HistoryClient: DependencyKey {
  static let testValue = Self(
    loadRetentionPolicy: { .defaults },
    writeAudio: { _, _ in throw HistoryClientError.unimplementedAudioWrite },
    deleteAudio: { _ in }, reconcile: { $0 },
  )

  static let liveValue: Self = {
    let vault = AudioVaultAccess(directoryURL: Channel.historyAudioDirectory)
    return Self(
      loadRetentionPolicy: {
        try SettingsStore(fileURL: Channel.settingsFile).load().retention
      },
      writeAudio: { recording, id in try await vault.write(recording, id: id) },
      deleteAudio: { ids in try await vault.delete(ids) },
      reconcile: { log in try await vault.reconcile(log) },
    )
  }()
}

// MARK: - HistoryClientError

private enum HistoryClientError: Error {
  case unimplementedAudioWrite
}

// MARK: - AudioVaultAccess

private actor AudioVaultAccess {
  // MARK: Lifecycle

  init(directoryURL: URL) {
    vault = AudioVault(directoryURL: directoryURL)
  }

  // MARK: Internal

  func write(_ recording: CanonicalRecording, id: UUID) throws -> AudioMetadata {
    try vault.write(recording, id: id)
  }

  func delete(_ ids: [UUID]) throws {
    try vault.delete(ids)
  }

  func reconcile(_ log: HistoryLog) throws -> HistoryLog {
    try vault.reconcile(log)
  }

  // MARK: Private

  private let vault: AudioVault
}

extension DependencyValues {
  var historyClient: HistoryClient {
    get { self[HistoryClient.self] }
    set { self[HistoryClient.self] = newValue }
  }
}
