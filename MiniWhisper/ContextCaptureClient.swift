import ComposableArchitecture
import FieldContext
import Foundation
import OSLog

let contextLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "context")

/// Reads the focused field just before delivery. `capture` is on the delivery path and never
/// retries or waits; `prewarmFrontmostApp` carries everything expensive and runs at recording
/// start instead.
@DependencyClient struct ContextCaptureClient: Sendable {
  var capture: @Sendable () async -> ContextCapture = { .unavailable(.noFocusedElement) }
  var prewarmFrontmostApp: @Sendable () async -> Void
}

extension ContextCaptureClient: DependencyKey {
  static let liveValue = Self(
    capture: { FocusedFieldReader.capture() },
    prewarmFrontmostApp: { await ChromiumAccessibility.prewarmFrontmostApp() })
}

extension DependencyValues {
  var contextCapture: ContextCaptureClient {
    get { self[ContextCaptureClient.self] }
    set { self[ContextCaptureClient.self] = newValue }
  }
}
