import ComposableArchitecture
import FieldContext
import Foundation
import OSLog

let contextLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "context")

// MARK: - ContextCaptureClient

/// Reads the focused field of whichever application is frontmost at the moment of the call. It
/// never retries or waits, so it is cheap enough to run on the delivery path; the same call is
/// also fired at release to warm the target's Accessibility tree, and `prewarmFrontmostApp`
/// carries the far more expensive Chromium wake at recording start.
@DependencyClient struct ContextCaptureClient {
  var capture: @Sendable () async -> ContextCapture = { .unavailable(.noFocusedElement) }
  var prewarmFrontmostApp: @Sendable () async -> Void
}

// MARK: DependencyKey

extension ContextCaptureClient: DependencyKey {
  static let liveValue = Self(
    capture: { FocusedFieldReader.capture() },
    prewarmFrontmostApp: { await ChromiumAccessibility.prewarmFrontmostApp() },
  )
}

extension DependencyValues {
  var contextCapture: ContextCaptureClient {
    get { self[ContextCaptureClient.self] }
    set { self[ContextCaptureClient.self] = newValue }
  }
}
