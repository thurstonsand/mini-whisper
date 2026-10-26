import ComposableArchitecture
import Foundation
import LocalCleanup
import ModelLibrary
import OSLog
import TranscriptCleanup

private let cleanupClientLogger = Logger(
  subsystem: "com.thurstonsand.MiniWhisper", category: "cleanup",
)

// MARK: - CleanupClient

/// The app's seam over `OpenAICompatibleCleanup`. Configuration and key travel with every call,
/// and a nil key is an endpoint that takes none,
/// rather than being held here: the pane edits both while a dictation may be in flight, and a
/// client that cached them would run the previous endpoint's request.
@DependencyClient struct CleanupClient {
  var clean: @Sendable (CleanupRequest, CleanupConfiguration, String?) async -> CleanupOutcome = {
    _, _, _ in .cancelled
  }

  var verify: @Sendable (CleanupConfiguration, String?) async -> VerificationOutcome = { _, _ in
    .cancelled
  }

  var listModels: @Sendable (CleanupConfiguration, String?) async -> ModelListing = { _, _ in
    .cancelled
  }

  /// S1-mini on this Mac, held to the same timeout a hosted pass is. It reads the transcript and
  /// nothing else.
  var cleanLocally: @Sendable (String, TimeInterval) async -> CleanupOutcome = { _, _ in
    .cancelled
  }

  /// Loads the local model ahead of the first dictation that needs it.
  var prepareLocal: @Sendable () async -> Void
  /// Lets go of the local model so its file can be deleted.
  var unloadLocal: @Sendable () async -> Void
}

// MARK: DependencyKey

extension CleanupClient: DependencyKey {
  static let liveValue: Self = {
    let s1Mini = S1Mini(library: .live)
    return Self(
      clean: { request, configuration, apiKey in
        await OpenAICompatibleCleanup(configuration: configuration, apiKey: apiKey).clean(request)
      },
      verify: { configuration, apiKey in
        await OpenAICompatibleCleanup(configuration: configuration, apiKey: apiKey).verify()
      },
      listModels: { configuration, apiKey in
        await OpenAICompatibleCleanup(configuration: configuration, apiKey: apiKey).listModels()
      },
      cleanLocally: { transcript, timeout in
        do {
          return try await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask { try await s1Mini.clean(transcript) }
            group.addTask {
              try await Task.sleep(for: .seconds(timeout))
              return nil
            }
            defer { group.cancelAll() }
            guard case let .some(.some(raw)) = try await group.next() else {
              return .failed(.timedOut(timeout))
            }
            // The same edge a hosted reply passes: empty or runaway text never replaces what
            // was heard.
            switch CleanupResponseShaping.conform(raw, transcript: transcript) {
            case let .success(cleaned):
              return .cleaned(cleaned)
            case let .failure(reason):
              return .failed(.degenerateResponse(reason))
            }
          }
        } catch is CancellationError {
          return .cancelled
        } catch {
          return .failed(.localModel(error.localizedDescription))
        }
      },
      prepareLocal: {
        do { try await s1Mini.prepare() } catch {
          cleanupClientLogger.error(
            "S1-mini prewarm failed: \(error.localizedDescription, privacy: .public)",
          )
        }
      },
      unloadLocal: { await s1Mini.unload() },
    )
  }()
}

extension DependencyValues {
  var cleanup: CleanupClient {
    get { self[CleanupClient.self] }
    set { self[CleanupClient.self] = newValue }
  }
}
