@testable import FieldContext
import Testing

// MARK: - TmuxListingTests

/// Fixtures are tmux 3.8's real answers to `TmuxListing.clientsQuery`, from two Ghostty tabs
/// attached to one server.
struct TmuxListingTests {
  @Test func `only the focused client of the terminal's own clients names a pane`() {
    let output = """
    on
    66307 attached,UTF-8 %0 66314 zsh
    66503 attached,focused,UTF-8 %1 66508 tmux
    70000 attached,focused,UTF-8 %4 70001 nvim
    """

    let clients = TmuxListing.focusedClients(in: output, among: [66307, 66503])

    #expect(clients == [TmuxClient(
      processID: 66503,
      paneID: "%1",
      panePID: 66508,
      command: "tmux",
    )])
  }

  @Test func `a server without focus events proves nothing about focus`() {
    let output = """
    off
    66307 attached,focused,UTF-8 %0 66314 zsh
    """

    #expect(TmuxListing.focusedClients(in: output, among: [66307]).isEmpty)
  }

  @Test func `a command with a space survives as one field`() {
    let output = """
    on
    9 attached,focused,UTF-8 %12 10 Claude Code
    """

    #expect(TmuxListing.focusedClients(in: output, among: [9]).first?.command == "Claude Code")
  }

  @Test func `a pane's state reads back its process and command`() {
    #expect(TmuxListing.paneState(in: "66706 cat\n") == TmuxPaneState(
      panePID: 66706,
      command: "cat",
    ))
    #expect(TmuxListing.paneState(in: "") == nil)
  }
}
