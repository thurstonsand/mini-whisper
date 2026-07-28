import ComposableArchitecture
import ServiceManagement

@DependencyClient struct LaunchAtLoginClient: Sendable {
  var isRegistered: @Sendable () -> Bool = { false }
  var setRegistered: @Sendable (Bool) throws -> Void
}

extension LaunchAtLoginClient: DependencyKey {
  static let liveValue = Self(
    isRegistered: { isRegistered(SMAppService.mainApp.status) },
    setRegistered: { registered in
      if registered {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    })

  /// `requiresApproval` means the login item exists but the user has switched it off in System
  /// Settings, so registering again would be a no-op; only the unregistered states are unchecked.
  static func isRegistered(_ status: SMAppService.Status) -> Bool {
    switch status {
    case .enabled, .requiresApproval: true
    case .notRegistered, .notFound: false
    @unknown default: false
    }
  }
}

extension DependencyValues {
  var launchAtLogin: LaunchAtLoginClient {
    get { self[LaunchAtLoginClient.self] }
    set { self[LaunchAtLoginClient.self] = newValue }
  }
}
