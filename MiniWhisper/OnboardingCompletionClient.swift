import ComposableArchitecture
import Foundation

// MARK: - OnboardingCompletionClient

@DependencyClient struct OnboardingCompletionClient {
  var isCompleted: @Sendable () -> Bool = { false }
  var markCompleted: @Sendable () throws -> Void
}

// MARK: DependencyKey

extension OnboardingCompletionClient: DependencyKey {
  static let liveValue = Self(
    isCompleted: { FileManager.default.fileExists(atPath: markerURL.path) },
    markCompleted: { try writeMarker(at: markerURL) },
  )
}

// MARK: - ModelDownloadConsentClient

@DependencyClient struct ModelDownloadConsentClient {
  var isConsented: @Sendable () -> Bool = { false }
  var markConsented: @Sendable () throws -> Void
}

// MARK: DependencyKey

extension ModelDownloadConsentClient: DependencyKey {
  static let testValue = Self(isConsented: { false }, markConsented: {})
  static let liveValue = Self(
    isConsented: { FileManager.default.fileExists(atPath: consentMarkerURL.path) },
    markConsented: { try writeMarker(at: consentMarkerURL) },
  )
}

extension DependencyValues {
  var onboardingCompletion: OnboardingCompletionClient {
    get { self[OnboardingCompletionClient.self] }
    set { self[OnboardingCompletionClient.self] = newValue }
  }

  var modelDownloadConsent: ModelDownloadConsentClient {
    get { self[ModelDownloadConsentClient.self] }
    set { self[ModelDownloadConsentClient.self] = newValue }
  }
}

private let markerURL = Channel.onboardingMarker
private let consentMarkerURL = Channel.modelDownloadConsentMarker

private func writeMarker(at url: URL) throws {
  try FileManager.default.createDirectory(
    at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
  )
  try Data().write(to: url, options: .atomic)
}
