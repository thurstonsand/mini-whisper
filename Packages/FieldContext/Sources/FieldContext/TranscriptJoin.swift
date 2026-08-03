/// The two deterministic decisions that join a transcript to the text already in the field.
///
/// Only the text before the insertion point matters: a paste replaces the selection, so the
/// selected text is on its way out. The window is bounded, so every rule reads the characters
/// immediately at the caret and consults `wasTruncated` where the missing text would change the
/// answer — counting quotes across the window would flip its verdict the moment the opening quote
/// falls off the front.
public struct TranscriptJoin: Equatable, Sendable {
  // MARK: Lifecycle

  public init(precedingText: String, wasTruncated: Bool = false) {
    needsLeadingSpace = Self.needsSeparator(after: precedingText, wasTruncated: wasTruncated)
    capitalizesFirstCharacter = Self.startsASentence(
      after: precedingText, wasTruncated: wasTruncated,
    )
  }

  // MARK: Public

  public let needsLeadingSpace: Bool
  /// A sentence start capitalizes the transcript's first letter; a continuation lowercases it,
  /// because the engine capitalizes the first word of every utterance it returns.
  public let capitalizesFirstCharacter: Bool

  public func apply(to transcript: String) -> String {
    guard let first = transcript.first else {
      return transcript
    }

    let separator = needsLeadingSpace && !first.isWhitespace ? " " : ""
    return separator + recased(transcript)
  }

  // MARK: Private

  private static let openingPunctuation: Set<Character> = ["(", "[", "{", "“", "‘", "«", "‹"]
  private static let ambiguousQuotes: Set<Character> = ["\"", "'"]
  private static let quotingPunctuation: Set<Character> = [
    "(", "[", "{", ")", "]", "}", "\"", "'", "“", "”", "‘", "’", "«", "»", "‹", "›",
  ]
  private static let sentenceEnding: Set<Character> = [".", "!", "?"]

  private static func firstLetterIndex(in transcript: String) -> String.Index? {
    var index = transcript.startIndex
    while index < transcript.endIndex {
      let character = transcript[index]
      guard character.isWhitespace || character.isPunctuation || character.isSymbol else {
        return index
      }
      index = transcript.index(after: index)
    }
    return nil
  }

  /// The one capital a continuation may keep. Anything longer that merely starts with `I` is a
  /// word, so `Italy` after a comma is lowercased — a proper noun costs one wrong letter, while
  /// leaving every engine capital in place costs one on every dictation.
  private static func startsWithFirstPersonI(_ transcript: Substring) -> Bool {
    guard transcript.first == "I" else {
      return false
    }
    guard let next = transcript.dropFirst().first else {
      return true
    }
    return !next.isLetter
  }

  private static func needsSeparator(after precedingText: String, wasTruncated: Bool) -> Bool {
    guard let last = precedingText.last else {
      return wasTruncated
    }
    guard !last.isWhitespace, !openingPunctuation.contains(last) else {
      return false
    }
    guard ambiguousQuotes.contains(last) else {
      return true
    }
    return isClosingQuote(precedingText.dropLast(), wasTruncated: wasTruncated)
  }

  /// A straight quote points both ways. What precedes it decides: a quote after a space or another
  /// opener opened a quotation, and a quote after a word or a closing mark shut one.
  private static func isClosingQuote(_ text: Substring, wasTruncated: Bool) -> Bool {
    guard let preceding = text.last else {
      return wasTruncated
    }
    if preceding.isWhitespace || openingPunctuation.contains(preceding) {
      return false
    }
    return true
  }

  private static func startsASentence(after precedingText: String, wasTruncated: Bool) -> Bool {
    var scan = Substring(precedingText)
    while let last = scan.last, last.isWhitespace || quotingPunctuation.contains(last) {
      scan = scan.dropLast()
    }
    guard let last = scan.last else {
      return !wasTruncated
    }
    // An ellipsis trails off mid-thought, so it ends no sentence however it was typed.
    guard last != "…", !scan.hasSuffix("..") else {
      return false
    }
    return sentenceEnding.contains(last)
  }

  /// The engine's capital is not always at index 0: an utterance can open with a quote, a bracket,
  /// or a space the target inherited. Only the first letter is re-cased, and only if punctuation
  /// and whitespace are all that precede it — a transcript that opens with a digit or a caseless
  /// script is left exactly as the engine wrote it.
  private func recased(_ transcript: String) -> String {
    guard let index = Self.firstLetterIndex(in: transcript) else {
      return transcript
    }
    let letter = String(transcript[index])
    let mapped: String
    if capitalizesFirstCharacter {
      mapped = letter.uppercased()
    } else {
      guard !Self.startsWithFirstPersonI(transcript[index...]) else {
        return transcript
      }
      mapped = letter.lowercased()
    }
    // Case mapping, not `isUppercase`: titlecase letters answer neither question usefully, and a
    // mapping that changes nothing (a digit, a caseless script) means there is nothing to re-case.
    guard mapped != letter else {
      return transcript
    }
    return transcript[..<index] + mapped + transcript[transcript.index(after: index)...]
  }
}
