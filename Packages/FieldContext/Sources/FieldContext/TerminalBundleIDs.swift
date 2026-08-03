/// Terminals expose their visible screen grid as one `AXTextArea` value rather than the document
/// being edited, so their text is unusable as context.
///
/// There is no mechanical way back in. A caret test was considered and rejected: Terminal.app
/// running nvim reports a nonzero, in-bounds `AXSelectedTextRange` for text that is still pure
/// grid, so the test admits exactly what it must exclude. A terminal graduates only when a
/// specific build is validated to serve document ranges.
public enum TerminalBundleIDs {
  public static let all: Set<String> = [
    "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "net.kovidgoyal.kitty",
    "com.github.wez.wezterm", "dev.warp.Warp-Stable", "io.alacritty", "org.alacritty",
    "co.zeit.hyper", "dev.zed.Zed.Helper",
  ]

  public static func contains(_ bundleID: String?) -> Bool {
    guard let bundleID else {
      return false
    }
    return all.contains(bundleID)
  }
}
