import Foundation

/// Where a hand-typed address becomes an API base. `TranscriptCleanup` appends `chat/completions`
/// and `models` to whatever it is given, so the guessing happens once, here, at the edge: a
/// missing scheme becomes `https`, and trailing slashes are shed so the appended path cannot
/// double up.
enum EndpointAddress {
  static func conform(_ text: String) -> URL? {
    var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return nil
    }
    if !trimmed.contains("://") {
      trimmed = "https://" + trimmed
    }
    while trimmed.hasSuffix("/") {
      trimmed.removeLast()
    }
    guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
          scheme == "https" || scheme == "http", url.host()?.isEmpty == false
    else {
      return nil
    }
    return url
  }

  /// The bases worth trying for a conformed address, best first.
  ///
  /// An address with a path is taken exactly as typed: the user said where the API is, and a
  /// client that went looking elsewhere would be overruling them. A bare host says nothing about
  /// where the API lives, so the conventional `/v1` is tried before the origin itself — nearly
  /// every OpenAI-compatible gateway documents `/v1` as its base, and probing the origin first
  /// would take a root 404 as the answer for a gateway that works perfectly well one path down.
  static func candidates(for url: URL) -> [URL] {
    guard !hasExplicitPath(url) else {
      return [url]
    }
    return [url.appending(path: "v1"), url]
  }

  static func hasExplicitPath(_ url: URL) -> Bool {
    let path = url.path()
    return !path.isEmpty && path != "/"
  }

  static func display(_ url: URL?) -> String {
    url?.absoluteString ?? ""
  }
}
