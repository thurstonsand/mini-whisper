// MARK: - TmuxClient

/// An attached tmux client whose terminal has focus, as its server describes it.
public struct TmuxClient: Equatable, Sendable {
  // MARK: Lifecycle

  public init(processID: Int32, paneID: String, panePID: Int32, command: String) {
    self.processID = processID
    self.paneID = paneID
    self.panePID = panePID
    self.command = command
  }

  // MARK: Public

  public let processID: Int32
  /// The client's active pane, `%N`. Pane ids name a process for the life of the server, not a
  /// position on screen, so one stays right after the client switches to another session.
  public let paneID: String
  public let panePID: Int32
  /// The pane's foreground command, which is what changes when an agent exits to its shell.
  public let command: String
}

// MARK: - TmuxPaneState

public struct TmuxPaneState: Equatable, Sendable {
  // MARK: Lifecycle

  public init(panePID: Int32, command: String) {
    self.panePID = panePID
    self.command = command
  }

  // MARK: Public

  public let panePID: Int32
  public let command: String
}

// MARK: - TmuxListing

/// The tmux commands target resolution sends, and how their answers are read. Fields are
/// space-separated because tmux replaces control characters, tabs included, in format output; the
/// command goes last since it is the only field that can contain a space.
public enum TmuxListing {
  public static let clientsQuery = [
    "show-options", "-gv", "focus-events", ";", "list-clients", "-F",
    "#{client_pid} #{client_flags} #{pane_id} #{pane_pid} #{pane_current_command}",
  ]

  public static func paneQuery(_ paneID: String) -> [String] {
    ["display-message", "-p", "-t", paneID, "#{pane_pid} #{pane_current_command}"]
  }

  /// The focused clients among `processIDs`. A server without `focus-events` never clears a
  /// client's `focused` flag, so every client it has reads focused forever; its answer proves
  /// nothing and counts as none.
  public static func focusedClients(in output: String, among processIDs: Set<Int32>)
    -> [TmuxClient]
  {
    var lines = output.split(separator: "\n", omittingEmptySubsequences: true)
    guard lines.first == "on" else {
      return []
    }
    lines.removeFirst()
    return lines.compactMap { line in
      let fields = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: false)
      guard fields.count == 5, let processID = Int32(fields[0]), processIDs.contains(processID),
            let panePID = Int32(fields[3])
      else {
        return nil
      }
      guard fields[1].split(separator: ",").contains("focused") else {
        return nil
      }
      return TmuxClient(
        processID: processID, paneID: String(fields[2]), panePID: panePID,
        command: String(fields[4]),
      )
    }
  }

  public static func paneState(in output: String) -> TmuxPaneState? {
    let line = output.split(separator: "\n").first ?? ""
    let fields = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
    guard fields.count == 2, let panePID = Int32(fields[0]) else {
      return nil
    }
    return TmuxPaneState(panePID: panePID, command: String(fields[1]))
  }
}
