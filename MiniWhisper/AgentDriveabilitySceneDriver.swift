import AppSettings
import ASREngine
import ComposableArchitecture
import Foundation
import History

#if DEBUG

  // MARK: - AgentSceneFiles

  enum AgentSceneFiles {
    static let command: URL = {
      guard let path = ProcessInfo.processInfo.environment["MINIWHISPER_AGENT_COMMAND_FILE"] else {
        preconditionFailure("Agent scene has no command file")
      }
      return URL(fileURLWithPath: path)
    }()

    static let result = URL(fileURLWithPath: "\(command.path).result")
  }

  // MARK: - AgentDriveabilitySceneDriver

  @MainActor final class AgentDriveabilitySceneDriver {
    // MARK: Lifecycle

    init(store: StoreOf<AppFeature>) {
      self.store = store
      commandFileURL = AgentSceneFiles.command
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
        store.send(.engineReadinessUpdated(.downloading(fraction)))
      case "model-ready":
        store.send(.engineReadinessUpdated(.ready))
      case "dictionary-save-failed":
        store.send(.settingsWindow(.dictionary(.persistenceFailed(.pane, String(fields[2])))))
      case "history-first-entries":
        store.send(.agentHistoryReplaced(firstHistoryEntries()))
        try? "history:first-entries".write(
          to: AgentSceneFiles.result, atomically: true, encoding: .utf8,
        )
      case "scene":
        guard let scene = AgentDriveabilityScene(rawValue: String(fields[2])) else {
          return
        }
        AgentSceneState.current?.reseed(for: scene)
        store.send(.agentScenePresented(scene))
        // The result file is the swap's barrier: a test that just posted a scene cannot tell a
        // stale window from the new one when both answer to the same identifiers.
        try? "scene:\(scene.rawValue)".write(
          to: AgentSceneFiles.result, atomically: true, encoding: .utf8,
        )
      default:
        return
      }
    }

    private func firstHistoryEntries() -> HistoryLog {
      let now = Date(timeIntervalSince1970: 1_754_352_000)
      return HistoryLog(entries: [
        HistoryEntry(
          id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
          createdAt: now,
          targetApp: TargetApp(bundleID: "com.apple.TextEdit", name: "TextEdit"),
          original: Transcription(
            text: "First live history entry", engine: "test-engine", transcribedAt: now,
          ),
          delivery: Delivery(text: "First live history entry", method: .pasted, detail: nil),
          audio: nil,
        ),
        HistoryEntry(
          id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
          createdAt: now.addingTimeInterval(-1),
          targetApp: TargetApp(bundleID: "com.apple.TextEdit", name: "TextEdit"),
          original: Transcription(
            text: "Second live history entry", engine: "test-engine", transcribedAt: now,
          ),
          delivery: Delivery(text: "Second live history entry", method: .pasted, detail: nil),
          audio: nil,
        ),
      ])
    }
  }
#else
  @MainActor final class AgentDriveabilitySceneDriver {
    init(store _: StoreOf<AppFeature>) {
      preconditionFailure()
    }
  }
#endif
