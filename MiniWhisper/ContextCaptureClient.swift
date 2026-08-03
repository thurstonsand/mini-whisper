import ComposableArchitecture
import FieldContext
import Foundation
import OSLog

let contextLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "context")

// MARK: - ContextCaptureSource

/// Which call site asked for the read. Both go through the same code; only the log tells them
/// apart, which is how the warm-up's effect on delivery cost can be measured after the fact.
enum ContextCaptureSource: String, Equatable {
  case warmUp = "warm-up"
  case delivery
}

// MARK: - ContextCaptureClient

/// Reads the focused field of whichever application is frontmost at the moment of the call. It
/// never retries or waits, so it is cheap enough to run on the delivery path; the same call is
/// also fired at release to warm the target's Accessibility tree, and `prewarmFrontmostApp`
/// carries the far more expensive Chromium wake at recording start.
@DependencyClient struct ContextCaptureClient {
  var capture: @Sendable (ContextCaptureSource) async -> ContextCapture = { _ in
    .unavailable(.noFocusedElement)
  }

  var prewarmFrontmostApp: @Sendable () async -> Void
}

// MARK: DependencyKey

extension ContextCaptureClient: DependencyKey {
  static let liveValue = Self(
    capture: { source in FocusedFieldReader.capture(source: source) },
    prewarmFrontmostApp: { await ChromiumAccessibility.prewarmFrontmostApp() },
  )
}

extension DependencyValues {
  var contextCapture: ContextCaptureClient {
    get { self[ContextCaptureClient.self] }
    set { self[ContextCaptureClient.self] = newValue }
  }
}
