import ComposableArchitecture
import Foundation
import TranscriptCleanup

// MARK: - CleanupClient

/// The app's seam over `OpenAICompatibleCleanup`. Configuration and key travel with every call
/// rather than being held here: the pane edits both while a dictation may be in flight, and a
/// client that cached them would run the previous endpoint's request.
@DependencyClient struct CleanupClient {
  var clean: @Sendable (CleanupRequest, CleanupConfiguration, String) async -> CleanupOutcome = {
    _, _, _ in .cancelled
  }

  var verify: @Sendable (CleanupConfiguration, String) async -> VerificationOutcome = { _, _ in
    .cancelled
  }

  var listModels: @Sendable (CleanupConfiguration, String) async -> ModelListing = { _, _ in
    .cancelled
  }
}

// MARK: DependencyKey

extension CleanupClient: DependencyKey {
  static let liveValue = Self(
    clean: { request, configuration, apiKey in
      await OpenAICompatibleCleanup(configuration: configuration, apiKey: apiKey).clean(request)
    },
    verify: { configuration, apiKey in
      await OpenAICompatibleCleanup(configuration: configuration, apiKey: apiKey).verify()
    },
    listModels: { configuration, apiKey in
      await OpenAICompatibleCleanup(configuration: configuration, apiKey: apiKey).listModels()
    },
  )
}

extension DependencyValues {
  var cleanup: CleanupClient {
    get { self[CleanupClient.self] }
    set { self[CleanupClient.self] = newValue }
  }
}
