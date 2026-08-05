import AppKit
import ComposableArchitecture
import Foundation

// MARK: - WorkspaceError

enum WorkspaceError: Error, Equatable {
  case openFailed(URL)
}

// MARK: - WorkspaceApplication

struct WorkspaceApplication: Equatable {
  var bundleID: String
  var name: String?
}

// MARK: - WorkspaceClient

@DependencyClient struct WorkspaceClient {
  var open: @Sendable (URL) async throws -> Void
  var frontmostApplication: @Sendable () async -> WorkspaceApplication?
}

// MARK: DependencyKey

extension WorkspaceClient: DependencyKey {
  static let testValue = Self(open: { _ in }, frontmostApplication: { nil })

  static let liveValue = Self(
    open: { url in
      let opened = await MainActor.run { NSWorkspace.shared.open(url) }
      guard opened else {
        throw WorkspaceError.openFailed(url)
      }
    },
    frontmostApplication: {
      await MainActor.run {
        guard let application = NSWorkspace.shared.frontmostApplication,
              let bundleID = application.bundleIdentifier
        else {
          return nil
        }
        return WorkspaceApplication(bundleID: bundleID, name: application.localizedName)
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
