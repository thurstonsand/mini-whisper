import Darwin
import FieldContext
import Foundation

// MARK: - TmuxPane

/// A tmux pane a dictation can be written to from outside, without focus: the binary and server
/// that own it, and enough of the pane to tell, at delivery, that it is still the one captured.
struct TmuxPane: Equatable {
  var executable: String
  var socket: String
  var paneID: String
  var panePID: pid_t
  /// The pane's session, which is the name a person knows the agent in it by.
  var session: String
  var command: String
}

// MARK: - TmuxPaneDelivery

enum TmuxPaneDelivery: Equatable {
  case delivered
  /// The pane, or its whole server, is no longer there.
  case gone
  /// The pane is there, but its foreground command is not the one captured: an agent that exited
  /// back to its shell would run a submitted prompt as a shell command.
  case changed
}

// MARK: - TmuxPanes

/// Finds the tmux pane behind an application's focused terminal surface, and writes into it.
///
/// Resolution reads only the process tree and tmux's own answers. A tmux client is a descendant
/// process of the terminal hosting it; its server is the peer of its connected unix socket; and
/// with `focus-events` on, the server knows which client's terminal has focus. That is enough to
/// name the pane on screen, and when that pane is itself running a tmux client — a nested session,
/// as Agent Switchboard's Deck is — the same walk continues inside it.
enum TmuxPanes {
  // MARK: Internal

  static func resolve(under rootPID: pid_t) -> TmuxPane? {
    var visited = 0
    return resolve(under: rootPID, depth: 0, visited: &visited)
  }

  static func deliver(_ text: String, submit: Bool, to pane: TmuxPane) -> TmuxPaneDelivery {
    let check = run(pane.executable, ["-S", pane.socket] + TmuxListing.paneQuery(pane.paneID))
    guard check.status == 0, let state = TmuxListing.paneState(in: check.output),
          state.panePID == pane.panePID
    else {
      return .gone
    }
    if submit, state.command != pane.command {
      return .changed
    }

    // The text travels on stdin, never as an argument: tmux reads an argument ending in `;` as a
    // command separator. `paste-buffer -p` brackets it only for a pane that asked for bracketed
    // paste, exactly as a terminal paste would. Return is written the same way rather than with
    // `send-keys`, which a pane in copy mode would take as a copy-mode key.
    let buffer = "miniwhisper-\(UUID().uuidString)"
    var arguments = [
      "-S", pane.socket, "load-buffer", "-b", buffer, "-", ";",
      "paste-buffer", "-d", "-p", "-b", buffer, "-t", pane.paneID,
    ]
    if submit {
      arguments += [
        ";", "set-buffer", "-b", buffer, "\r", ";", "paste-buffer", "-d", "-b", buffer, "-t",
        pane.paneID,
      ]
    }
    return run(pane.executable, arguments, input: text).status == 0 ? .delivered : .gone
  }

  // MARK: Private

  private struct Output {
    var status: Int32
    var output: String
  }

  private struct UnixSocket {
    var socket: UInt64
    var peer: UInt64
    var ownPath: String
    var peerPath: String
  }

  private static let maximumDepth = 4
  private static let maximumProcesses = 512

  private static func resolve(under rootPID: pid_t, depth: Int, visited: inout Int) -> TmuxPane? {
    guard depth < maximumDepth else {
      return nil
    }
    var clientsByServer: [String: (executable: String, processIDs: Set<pid_t>)] = [:]
    for processID in descendants(of: rootPID, visited: &visited) {
      guard let executable = executablePath(processID),
            (executable as NSString).lastPathComponent == "tmux"
      else {
        continue
      }
      for socket in connectedUnixSockets(processID) {
        clientsByServer[socket, default: (executable, [])].processIDs.insert(processID)
      }
    }

    var focused: [(socket: String, executable: String, client: TmuxClient)] = []
    for (socket, server) in clientsByServer {
      let answer = run(server.executable, ["-S", socket] + TmuxListing.clientsQuery)
      guard answer.status == 0 else {
        continue
      }
      for client in TmuxListing.focusedClients(in: answer.output, among: server.processIDs) {
        focused.append((socket, server.executable, client))
      }
    }
    // Two focused clients is two terminals each claiming the user; guessing between them is how
    // a dictation lands in the wrong agent.
    guard focused.count == 1, let hit = focused.first else {
      return nil
    }
    return resolve(under: hit.client.panePID, depth: depth + 1, visited: &visited)
      ?? TmuxPane(
        executable: hit.executable, socket: hit.socket, paneID: hit.client.paneID,
        panePID: hit.client.panePID, session: hit.client.session, command: hit.client.command,
      )
  }

  private static func descendants(of rootPID: pid_t, visited: inout Int) -> [pid_t] {
    var found: [pid_t] = []
    var pending = [rootPID]
    while let processID = pending.popLast(), visited < maximumProcesses {
      let children = childProcesses(of: processID)
      visited += children.count
      found += children
      pending += children
    }
    return found
  }

  private static func childProcesses(of processID: pid_t) -> [pid_t] {
    var buffer = [pid_t](repeating: 0, count: 256)
    let count = proc_listchildpids(
      processID, &buffer, Int32(buffer.count * MemoryLayout<pid_t>.size),
    )
    return count > 0 ? Array(buffer.prefix(Int(count))) : []
  }

  private static func executablePath(_ processID: pid_t) -> String? {
    var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN) * 4)
    let length = proc_pidpath(processID, &buffer, UInt32(buffer.count))
    guard length > 0 else {
      return nil
    }
    return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
  }

  /// The server a client talks to is the peer address of its connected unix socket. Reading it
  /// here, rather than reconstructing it from `-L`, `-S`, `TMUX`, and `TMUX_TMPDIR`, is right for
  /// every way the client could have been started. A client that started its own server talks to
  /// it over a socketpair, which has no address; the tmux process holding the other end is that
  /// server, and its listening socket is the path.
  private static func connectedUnixSockets(_ processID: pid_t) -> [String] {
    unixSockets(processID).compactMap { socket in
      if !socket.peerPath.isEmpty {
        return socket.peerPath
      }
      guard socket.peer != 0 else {
        return nil
      }
      return listeningPath(ofServerHolding: socket.peer)
    }
  }

  private static func listeningPath(ofServerHolding socket: UInt64) -> String? {
    let count = proc_listallpids(nil, 0)
    guard count > 0 else {
      return nil
    }
    var processIDs = [pid_t](repeating: 0, count: Int(count) + 64)
    let filled = proc_listallpids(&processIDs, Int32(processIDs.count * MemoryLayout<pid_t>.size))
    for processID in processIDs.prefix(Int(max(filled, 0)))
      where executablePath(processID).map({ ($0 as NSString).lastPathComponent }) == "tmux"
    {
      let sockets = unixSockets(processID)
      if sockets.contains(where: { $0.socket == socket }) {
        return sockets.first { !$0.ownPath.isEmpty }?.ownPath
      }
    }
    return nil
  }

  private static func unixSockets(_ processID: pid_t) -> [UnixSocket] {
    let size = proc_pidinfo(processID, PROC_PIDLISTFDS, 0, nil, 0)
    guard size > 0 else {
      return []
    }
    var descriptors = [proc_fdinfo](
      repeating: proc_fdinfo(), count: Int(size) / MemoryLayout<proc_fdinfo>.size,
    )
    let filled = proc_pidinfo(processID, PROC_PIDLISTFDS, 0, &descriptors, size)
    guard filled > 0 else {
      return []
    }
    var sockets: [UnixSocket] = []
    for descriptor in descriptors.prefix(Int(filled) / MemoryLayout<proc_fdinfo>.size)
      where descriptor.proc_fdtype == PROX_FDTYPE_SOCKET
    {
      var info = socket_fdinfo()
      let infoSize = Int32(MemoryLayout<socket_fdinfo>.size)
      guard proc_pidfdinfo(
        processID, descriptor.proc_fd, PROC_PIDFDSOCKETINFO, &info, infoSize,
      ) == infoSize,
        info.psi.soi_family == AF_UNIX
      else {
        continue
      }
      let unix = info.psi.soi_proto.pri_un
      sockets.append(
        UnixSocket(
          socket: info.psi.soi_so, peer: unix.unsi_conn_so,
          ownPath: path(unix.unsi_addr.ua_sun), peerPath: path(unix.unsi_caddr.ua_sun),
        ),
      )
    }
    return sockets
  }

  private static func path(_ address: sockaddr_un) -> String {
    var address = address
    return withUnsafeBytes(of: &address.sun_path) { bytes in
      String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
  }

  /// `posix_spawn` rather than `Process`: measured at 5 ms a call against `Process`'s 70, which
  /// is the difference between a resolution that fits beside a recording start and one that
  /// does not.
  private static func run(_ executable: String, _ arguments: [String], input: String = "")
    -> Output
  {
    var stdinPipe: [Int32] = [-1, -1]
    var stdoutPipe: [Int32] = [-1, -1]
    guard pipe(&stdinPipe) == 0 else {
      return Output(status: -1, output: "")
    }
    guard pipe(&stdoutPipe) == 0 else {
      close(stdinPipe[0])
      close(stdinPipe[1])
      return Output(status: -1, output: "")
    }

    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    posix_spawn_file_actions_adddup2(&actions, stdinPipe[0], STDIN_FILENO)
    posix_spawn_file_actions_adddup2(&actions, stdoutPipe[1], STDOUT_FILENO)
    posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)
    for descriptor in stdinPipe + stdoutPipe {
      posix_spawn_file_actions_addclose(&actions, descriptor)
    }

    // Captures, deliveries, and Escape checks spawn at once; a child holding another's pipe
    // would hold off that one's end of input.
    var attributes: posix_spawnattr_t?
    posix_spawnattr_init(&attributes)
    defer { posix_spawnattr_destroy(&attributes) }
    posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))

    let argv = ([executable] + arguments).map { strdup($0) } + [nil]
    defer { argv.forEach { free($0) } }
    var processID: pid_t = 0
    let spawned = posix_spawn(&processID, executable, &actions, &attributes, argv, [nil])
    close(stdinPipe[0])
    close(stdoutPipe[1])

    // A tmux that exits before reading its input must fail the write, not kill the app.
    _ = fcntl(stdinPipe[1], F_SETNOSIGPIPE, 1)
    if spawned == 0 {
      let bytes = Array(input.utf8)
      var written = 0
      while written < bytes.count {
        let count = bytes.withUnsafeBytes { buffer in
          write(stdinPipe[1], buffer.baseAddress! + written, buffer.count - written)
        }
        if count == -1, errno == EINTR {
          continue
        }
        guard count > 0 else {
          break
        }
        written += count
      }
    }
    close(stdinPipe[1])

    var output = [UInt8]()
    var chunk = [UInt8](repeating: 0, count: 4096)
    while true {
      let count = read(stdoutPipe[0], &chunk, chunk.count)
      if count == -1, errno == EINTR {
        continue
      }
      guard count > 0 else {
        break
      }
      output += chunk.prefix(count)
    }
    close(stdoutPipe[0])

    guard spawned == 0 else {
      return Output(status: -1, output: "")
    }
    var status: Int32 = 0
    while waitpid(processID, &status, 0) == -1, errno == EINTR {}
    let exitCode = (status & 0x7F) == 0 ? (status >> 8) & 0xFF : -1
    return Output(status: exitCode, output: String(decoding: output, as: UTF8.self))
  }
}
