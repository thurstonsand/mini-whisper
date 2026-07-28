import AppKit
import ComposableArchitecture
import Foundation

enum WorkspaceError: Error, Equatable, Sendable { case openFailed(URL) }

@DependencyClient struct WorkspaceClient: Sendable {
  var open: @Sendable (URL) async throws -> Void
}

extension WorkspaceClient: DependencyKey {
  static let liveValue = Self(open: { url in
    let opened = await MainActor.run { NSWorkspace.shared.open(url) }
    guard opened else { throw WorkspaceError.openFailed(url) }
  })
}

extension DependencyValues {
  var workspace: WorkspaceClient {
    get { self[WorkspaceClient.self] }
    set { self[WorkspaceClient.self] = newValue }
  }
}
