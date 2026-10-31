import ComposableArchitecture
import FieldContext
import Foundation
import OSLog

let contextLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "context")

// MARK: - ContextCaptureClient

/// Reads the text around the selection of the field a target captured. It never retries or
/// waits, so it is cheap enough to run on the delivery path; `prewarmFrontmostApp` carries the
/// far more expensive Chromium wake at recording start.
@DependencyClient struct ContextCaptureClient {
  var capture: @Sendable (DeliveryTarget) async -> ContextCapture = { _ in
    .unavailable(.noFocusedElement)
  }

  var prewarmFrontmostApp: @Sendable () async -> Void
}

// MARK: DependencyKey

extension ContextCaptureClient: DependencyKey {
  static let liveValue = Self(
    capture: { target in FocusedFieldReader.capture(target) },
    prewarmFrontmostApp: { await ChromiumAccessibility.prewarmFrontmostApp() },
  )
}

extension DependencyValues {
  var contextCapture: ContextCaptureClient {
    get { self[ContextCaptureClient.self] }
    set { self[ContextCaptureClient.self] = newValue }
  }
}
