/// The two deterministic decisions that join a transcript to the text already in the field.
///
/// Only the text before the insertion point matters: a paste replaces the selection, so the
/// selected text is on its way out. The window is bounded, so every rule reads the characters
/// immediately at the caret and consults `wasTruncated` where the missing text would change the
/// answer — counting quotes across the window would flip its verdict the moment the opening quote
/// falls off the front.
public struct TranscriptJoin: Equatable, Sendable {
  public let needsLeadingSpace: Bool
  public let capitalizesFirstCharacter: Bool

  public init(precedingText: String, wasTruncated: Bool = false) {
    needsLeadingSpace = Self.needsSeparator(after: precedingText, wasTruncated: wasTruncated)
    capitalizesFirstCharacter = Self.startsASentence(
      after: precedingText, wasTruncated: wasTruncated)
  }

  public func apply(to transcript: String) -> String {
    guard let first = transcript.first else { return transcript }

    let body =
      capitalizesFirstCharacter && first.isLowercase
      ? first.uppercased() + transcript.dropFirst() : transcript
    let separator = needsLeadingSpace && !first.isWhitespace ? " " : ""
    return separator + body
  }

  private static let openingPunctuation: Set<Character> = ["(", "[", "{", "“", "‘", "«", "‹"]
  private static let ambiguousQuotes: Set<Character> = ["\"", "'"]
  private static let quotingPunctuation: Set<Character> = [
    "(", "[", "{", ")", "]", "}", "\"", "'", "“", "”", "‘", "’", "«", "»", "‹", "›",
  ]
  private static let sentenceEnding: Set<Character> = [".", "!", "?"]

  private static func needsSeparator(after precedingText: String, wasTruncated: Bool) -> Bool {
    guard let last = precedingText.last else { return wasTruncated }
    guard !last.isWhitespace, !openingPunctuation.contains(last) else { return false }
    guard ambiguousQuotes.contains(last) else { return true }
    return isClosingQuote(precedingText.dropLast(), wasTruncated: wasTruncated)
  }

  /// A straight quote points both ways. What precedes it decides: a quote after a space or another
  /// opener opened a quotation, and a quote after a word or a closing mark shut one.
  private static func isClosingQuote(_ text: Substring, wasTruncated: Bool) -> Bool {
    guard let preceding = text.last else { return wasTruncated }
    if preceding.isWhitespace || openingPunctuation.contains(preceding) { return false }
    return true
  }

  private static func startsASentence(after precedingText: String, wasTruncated: Bool) -> Bool {
    var scan = Substring(precedingText)
    while let last = scan.last, last.isWhitespace || quotingPunctuation.contains(last) {
      scan = scan.dropLast()
    }
    guard let last = scan.last else { return !wasTruncated }
    // An ellipsis trails off mid-thought, so it ends no sentence however it was typed.
    guard last != "…", !scan.hasSuffix("..") else { return false }
    return sentenceEnding.contains(last)
  }
}
