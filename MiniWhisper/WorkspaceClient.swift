import AppKit
import ComposableArchitecture
import Foundation

// MARK: - WorkspaceError

enum WorkspaceError: Error, Equatable {
  case openFailed(URL)
}

// MARK: - WorkspaceClient

@DependencyClient struct WorkspaceClient {
  var open: @Sendable (URL) async throws -> Void
}

// MARK: DependencyKey

extension WorkspaceClient: DependencyKey {
  static let liveValue = Self(
    open: { url in
      let opened = await MainActor.run { NSWorkspace.shared.open(url) }
      guard opened else {
        throw WorkspaceError.openFailed(url)
      }
    },
  )
}

extension DependencyValues {
  var workspace: WorkspaceClient {
    get { self[WorkspaceClient.self] }
    set { self[WorkspaceClient.self] = newValue }
  }
}
