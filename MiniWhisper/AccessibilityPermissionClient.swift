import ApplicationServices
import ComposableArchitecture

// MARK: - AccessibilityPermissionClient

/// One Accessibility grant runs the hotkey tap, the synthetic ⌘V, and the field read, so one client
/// answers for all three rather than each consumer asking macOS its own way.
@DependencyClient struct AccessibilityPermissionClient {
  var hasPermission: @Sendable () -> Bool = { false }
  var requestPermission: @MainActor @Sendable () -> Bool = { false }
}

// MARK: DependencyKey

extension AccessibilityPermissionClient: DependencyKey {
  static let liveValue = Self(
    // CGPreflightPostEventAccess caches its first answer for the life of the process, so a grant
    // made while MiniWhisper runs would need a relaunch to be seen; AXIsProcessTrusted reports
    // grants and revocations live.
    hasPermission: { AXIsProcessTrusted() },
    // CGRequestPostEventAccess prompts unreliably and leaves no MiniWhisper row in Accessibility;
    // the Accessibility trust prompt both asks and seeds the row.
    requestPermission: {
      // kAXTrustedCheckOptionPrompt is imported as shared mutable state, so spell its value out.
      AXIsProcessTrustedWithOptions(
        ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary,
      )
    },
  )
}

extension DependencyValues {
  var accessibilityPermission: AccessibilityPermissionClient {
    get { self[AccessibilityPermissionClient.self] }
    set { self[AccessibilityPermissionClient.self] = newValue }
  }
}
