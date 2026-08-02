import AppKit
import ComposableArchitecture
import Foundation

enum WorkspaceError: Error, Equatable, Sendable {
  case openFailed(URL)
  case relaunchFailed(String)
}

@DependencyClient struct WorkspaceClient: Sendable {
  var open: @Sendable (URL) async throws -> Void
  var relaunch: @Sendable () async throws -> Void
}

extension WorkspaceClient: DependencyKey {
  static let liveValue = Self(
    open: { url in
      let opened = await MainActor.run { NSWorkspace.shared.open(url) }
      guard opened else { throw WorkspaceError.openFailed(url) }
    },
    relaunch: {
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.createsNewApplicationInstance = true
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
        { _, error in
          if let error {
            continuation.resume(throwing: WorkspaceError.relaunchFailed(error.localizedDescription))
          } else {
            continuation.resume()
          }
        }
      }
      await MainActor.run { NSApp.terminate(nil) }
    })
}

extension DependencyValues {
  var workspace: WorkspaceClient {
    get { self[WorkspaceClient.self] }
    set { self[WorkspaceClient.self] = newValue }
  }
}
