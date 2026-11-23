// MARK: - TextShape

/// What a metrics line may say about a piece of dictated text: its size and the two edges cleanup
/// instructions most often govern, never the text itself.
public struct TextShape: Encodable, Equatable, Sendable {
  // MARK: Lifecycle

  public init(_ text: String) {
    chars = text.count
    words = text.split(whereSeparator: \.isWhitespace).count
    upper = text.reduce(0) { $0 + ($1.isUppercase ? 1 : 0) }
    first = Self.firstLetter(of: text)
    end = Self.ending(of: text)
  }

  // MARK: Public

  public enum FirstLetter: String, Encodable, Sendable {
    case upper
    case lower
    /// The text opens with a digit, a caseless script, or has no letter at all.
    case none
  }

  public enum Ending: String, Encodable, Sendable {
    case period
    case question
    case exclamation
    case ellipsis
    /// Any other mark, such as a colon or a dash.
    case other
    /// A letter or digit: the text stops without punctuation.
    case none
  }

  public let chars: Int
  public let words: Int
  /// Uppercase letters anywhere in the text.
  public let upper: Int
  public let first: FirstLetter
  /// The last mark before any closing quotes and brackets, so `"Done."` ends in a period.
  public let end: Ending

  // MARK: Private

  private static let closers: Set<Character> = [
    ")", "]", "}", "\"", "'", "”", "’", "»", "›",
  ]

  /// The same letter delivery's join re-cases: the first character that is not whitespace,
  /// punctuation, or a symbol.
  private static func firstLetter(of text: String) -> FirstLetter {
    guard let character = text.first(where: {
      !($0.isWhitespace || $0.isPunctuation || $0.isSymbol)
    }) else {
      return .none
    }
    if character.isUppercase {
      return .upper
    }
    return character.isLowercase ? .lower : .none
  }

  private static func ending(of text: String) -> Ending {
    var scan = Substring(text)
    while let last = scan.last, last.isWhitespace || closers.contains(last) {
      scan = scan.dropLast()
    }
    guard let last = scan.last else {
      return .none
    }
    if last == "…" || scan.hasSuffix("..") {
      return .ellipsis
    }
    switch last {
    case ".":
      return .period
    case "?":
      return .question
    case "!":
      return .exclamation
    default:
      return last.isLetter || last.isNumber ? .none : .other
    }
  }
}

// MARK: - TextChange

/// How far cleanup moved the text from what the engine heard.
public struct TextChange: Encodable, Equatable, Sendable {
  // MARK: Lifecycle

  public init(from raw: String, to cleaned: String) {
    edit = Self.distance(Array(raw.unicodeScalars), Array(cleaned.unicodeScalars))
    wordsSame = Self.words(raw) == Self.words(cleaned)
  }

  // MARK: Public

  /// Levenshtein distance in Unicode scalars.
  public let edit: Int
  /// The same words once case and punctuation are set aside: cleanup only re-cased and
  /// re-punctuated.
  public let wordsSame: Bool

  // MARK: Private

  private static func words(_ text: String) -> [String] {
    text.lowercased()
      .split { $0.isWhitespace || $0.isPunctuation }
      .map(String.init)
  }

  private static func distance(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar]) -> Int {
    guard !a.isEmpty else {
      return b.count
    }
    var previous = Array(0 ... b.count)
    var current = previous
    for i in 1 ... a.count {
      current[0] = i
      for j in stride(from: 1, through: b.count, by: 1) {
        current[j] = a[i - 1] == b[j - 1]
          ? previous[j - 1]
          : 1 + min(previous[j - 1], previous[j], current[j - 1])
      }
      swap(&previous, &current)
    }
    return previous[b.count]
  }
}
