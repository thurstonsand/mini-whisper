import AVFAudio
import ComposableArchitecture
import Foundation

// MARK: - PlaybackCompletion

/// How a playback ended. Reported rather than inferred from cancellation, so starting one
/// recording and stopping another are the same operation from the reducer's side: the player
/// already allows only one at a time.
enum PlaybackCompletion: Equatable {
  case finished
  case interrupted
}

// MARK: - HistoryPlaybackClient

@DependencyClient struct HistoryPlaybackClient {
  var play: @Sendable (UUID) async throws -> PlaybackCompletion
  var stop: @Sendable () async -> Void
}

// MARK: DependencyKey

extension HistoryPlaybackClient: DependencyKey {
  static let testValue = Self(play: { _ in .finished }, stop: {})

  static let liveValue: Self = {
    let player = HistoryAudioPlayer(directoryURL: Channel.historyAudioDirectory)
    return Self(play: { try await player.play($0) }, stop: { await player.stop() })
  }()
}

extension DependencyValues {
  var historyPlayback: HistoryPlaybackClient {
    get { self[HistoryPlaybackClient.self] }
    set { self[HistoryPlaybackClient.self] = newValue }
  }
}

// MARK: - HistoryAudioPlayer

private actor HistoryAudioPlayer {
  // MARK: Lifecycle

  init(directoryURL: URL) {
    self.directoryURL = directoryURL
  }

  // MARK: Internal

  func play(_ id: UUID) async throws -> PlaybackCompletion {
    finish(.success(.interrupted))

    let url = directoryURL.appendingPathComponent("\(id.uuidString).wav")
    let player = try AVAudioPlayer(contentsOf: url)
    let token = UUID()
    let delegate = PlaybackDelegate { [weak self] playedSuccessfully in
      Task { await self?.playbackFinished(token: token, successfully: playedSuccessfully) }
    }
    currentToken = token
    audioPlayer = player
    audioPlayerDelegate = delegate
    player.delegate = delegate

    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      guard player.play() else {
        finish(.failure(HistoryPlaybackError.couldNotStart))
        return
      }
    }
  }

  func stop() {
    finish(.success(.interrupted))
  }

  // MARK: Private

  private let directoryURL: URL
  private var audioPlayer: AVAudioPlayer?
  private var audioPlayerDelegate: PlaybackDelegate?
  /// Identifies the playback a delegate callback belongs to, so a late callback from a recording
  /// that was already stopped cannot end the one that replaced it.
  private var currentToken: UUID?
  private var continuation: CheckedContinuation<PlaybackCompletion, Error>?

  private func playbackFinished(token: UUID, successfully: Bool) {
    guard token == currentToken else {
      return
    }
    finish(successfully ? .success(.finished) : .failure(HistoryPlaybackError.decodeFailed))
  }

  /// Ending a playback silences it here rather than leaving that to deallocation, so replacing
  /// one recording with another and stopping it outright do the same thing.
  private func finish(_ result: Result<PlaybackCompletion, Error>) {
    audioPlayer?.stop()
    audioPlayer = nil
    audioPlayerDelegate = nil
    currentToken = nil
    let continuation = continuation
    self.continuation = nil
    continuation?.resume(with: result)
  }
}

// MARK: - PlaybackDelegate

private final class PlaybackDelegate: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
  // MARK: Lifecycle

  init(didFinish: @escaping @Sendable (Bool) -> Void) {
    self.didFinish = didFinish
  }

  // MARK: Internal

  func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully flag: Bool) {
    didFinish(flag)
  }

  // MARK: Private

  private let didFinish: @Sendable (Bool) -> Void
}

// MARK: - HistoryPlaybackError

private enum HistoryPlaybackError: Error {
  case couldNotStart
  case decodeFailed
}
