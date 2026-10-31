// MARK: - TmuxClient

/// An attached tmux client whose terminal has focus, as its server describes it.
public struct TmuxClient: Equatable, Sendable {
  // MARK: Lifecycle

  public init(processID: Int32, paneID: String, panePID: Int32, session: String, command: String) {
    self.processID = processID
    self.paneID = paneID
    self.panePID = panePID
    self.session = session
    self.command = command
  }

  // MARK: Public

  public let processID: Int32
  /// The client's active pane, `%N`. Pane ids name a process for the life of the server, not a
  /// position on screen, so one stays right after the client switches to another session.
  public let paneID: String
  public let panePID: Int32
  /// The session the pane belongs to, which is how a person names the agent in it.
  public let session: String
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
/// space-separated because tmux replaces control characters, tabs included, in format output. The
/// session and command can contain anything, so tmux quotes them (`q:`), which backslash-escapes
/// every space inside them.
public enum TmuxListing {
  // MARK: Public

  public static let clientsQuery = [
    "show-options", "-gv", "focus-events", ";", "list-clients", "-F",
    "#{client_pid} #{client_flags} #{pane_id} #{pane_pid} #{q:session_name} #{q:pane_current_command}",
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
      let fields = quotedFields(line)
      guard fields.count == 6, let processID = Int32(fields[0]), processIDs.contains(processID),
            let panePID = Int32(fields[3])
      else {
        return nil
      }
      guard fields[1].split(separator: ",").contains("focused") else {
        return nil
      }
      return TmuxClient(
        processID: processID, paneID: fields[2], panePID: panePID, session: fields[4],
        command: fields[5],
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

  // MARK: Private

  /// Splits on the spaces tmux left bare, and drops the backslashes it escaped the rest with.
  private static func quotedFields(_ line: Substring) -> [String] {
    var fields = [""]
    var escaped = false
    for character in line {
      if escaped {
        fields[fields.count - 1].append(character)
        escaped = false
      } else if character == "\\" {
        escaped = true
      } else if character == " " {
        fields.append("")
      } else {
        fields[fields.count - 1].append(character)
      }
    }
    return fields
  }
}
