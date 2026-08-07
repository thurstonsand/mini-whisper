import AppSettings
import ASREngine
import ComposableArchitecture
import Foundation

#if DEBUG
  @MainActor final class AgentDriveabilitySceneDriver {
    // MARK: Lifecycle

    init(store: StoreOf<AppFeature>, refreshMenu: @escaping @MainActor () -> Void) {
      self.store = store
      self.refreshMenu = refreshMenu
      guard let path = ProcessInfo.processInfo.environment["MINIWHISPER_AGENT_COMMAND_FILE"] else {
        preconditionFailure("Agent scene has no command file")
      }
      commandFileURL = URL(fileURLWithPath: path)
      commandTask = Task { [weak self] in
        // The sequence prefix makes identical payloads distinct while whole-file comparison rejects
        // partial rewrites.
        var lastCommand = ""
        while !Task.isCancelled {
          try? await Task.sleep(for: .milliseconds(50))
          guard let self,
                let command = try? String(contentsOf: commandFileURL, encoding: .utf8),
                command != lastCommand
          else {
            continue
          }
          lastCommand = command
          receive(command)
        }
      }
    }

    deinit { commandTask?.cancel() }

    // MARK: Private

    private let store: StoreOf<AppFeature>
    private let commandFileURL: URL
    private let refreshMenu: @MainActor () -> Void
    private var commandTask: Task<Void, Never>?

    private func receive(_ command: String) {
      let fields = command.split(separator: "|", omittingEmptySubsequences: false)
      guard fields.count == 3 else {
        return
      }
      switch fields[1] {
      case "pill-level":
        guard let level = Float(fields[2]) else {
          return
        }
        store.send(.pill(.levelUpdated(level)))
      case "model-progress":
        guard let fraction = Double(fields[2]) else {
          return
        }
        store.send(.onboarding(.engineReadinessUpdated(.downloading(fraction))))
      case "model-ready":
        store.send(.onboarding(.engineReadinessUpdated(.ready)))
      case "launch-at-login":
        store.send(.launchAtLoginUpdated(fields[2] == "true"))
        refreshMenu()
      default:
        return
      }
    }
  }
#else
  @MainActor final class AgentDriveabilitySceneDriver {
    init(store _: StoreOf<AppFeature>, refreshMenu _: @escaping @MainActor () -> Void) {
      preconditionFailure()
    }
  }
#endif
