import Foundation

// MARK: - TranscriptCorrector

struct TranscriptCorrector {
  // MARK: Lifecycle

  init(dictionary: TranscriptionDictionary) {
    rules = dictionary.corrections.map {
      Rule(source: $0.misspelling, replacement: $0.text, priority: 0)
    } + dictionary.vocabulary.map {
      Rule(source: $0, replacement: $0, priority: 1)
    }
  }

  // MARK: Internal

  func apply(to transcript: String) -> String {
    guard !transcript.isEmpty, !rules.isEmpty else {
      return transcript
    }

    let fullRange = NSRange(transcript.startIndex ..< transcript.endIndex, in: transcript)
    let candidates = rules.flatMap { rule in
      rule.regularExpression.matches(in: transcript, range: fullRange).map {
        Match(range: $0.range, rule: rule)
      }
    }
    .sorted { lhs, rhs in
      if lhs.range.length != rhs.range.length {
        return lhs.range.length > rhs.range.length
      }
      if lhs.range.location != rhs.range.location {
        return lhs.range.location < rhs.range.location
      }
      return lhs.rule.priority < rhs.rule.priority
    }
    var matches: [Match] = []
    for candidate in candidates
      where !matches.contains(where: { NSIntersectionRange($0.range, candidate.range).length > 0 })
    {
      matches.append(candidate)
    }
    matches.sort { $0.range.location < $1.range.location }

    var result = ""
    var consumedLocation = 0
    for match in matches {
      result += substring(
        of: transcript,
        in: NSRange(location: consumedLocation, length: match.range.location - consumedLocation),
      )
      var replacement = match.rule.replacement
      if isSentenceStart(in: transcript, at: match.range.location), isAllLowercase(replacement) {
        replacement = capitalizingFirstLetter(of: replacement)
      }
      result += replacement
      consumedLocation = NSMaxRange(match.range)
    }
    result += substring(
      of: transcript,
      in: NSRange(location: consumedLocation, length: fullRange.length - consumedLocation),
    )
    return result
  }

  // MARK: Private

  private struct Rule {
    // MARK: Lifecycle

    init(source: String, replacement: String, priority: Int) {
      self.replacement = replacement
      self.priority = priority
      let escaped = NSRegularExpression.escapedPattern(for: source)
      let leftBoundary = source.first?.isWordCharacter == true ? "(?<![\\p{L}\\p{N}_])" : ""
      let rightBoundary = source.last?.isWordCharacter == true ? "(?![\\p{L}\\p{N}_])" : ""
      regularExpression = try! NSRegularExpression(
        pattern: "\(leftBoundary)\(escaped)\(rightBoundary)", options: [.caseInsensitive],
      )
    }

    // MARK: Internal

    let replacement: String
    let priority: Int
    let regularExpression: NSRegularExpression
  }

  private struct Match {
    let range: NSRange
    let rule: Rule
  }

  private let rules: [Rule]

  private func substring(of text: String, in range: NSRange) -> String {
    guard let range = Range(range, in: text) else {
      preconditionFailure("A regular-expression range did not belong to its transcript")
    }
    return String(text[range])
  }

  private func isSentenceStart(in transcript: String, at location: Int) -> Bool {
    let prefix = substring(of: transcript, in: NSRange(location: 0, length: location))
    for character in prefix.reversed() {
      if character.isWhitespace || "\"'“”‘’([{«".contains(character) {
        continue
      }
      return ".!?".contains(character)
    }
    return true
  }

  private func isAllLowercase(_ text: String) -> Bool {
    text == text.lowercased()
  }

  private func capitalizingFirstLetter(of text: String) -> String {
    guard let index = text.firstIndex(where: { $0.isLetter }) else {
      return text
    }
    var result = text
    result.replaceSubrange(index ... index, with: String(text[index]).uppercased())
    return result
  }
}

private extension Character {
  var isWordCharacter: Bool {
    isLetter || isNumber || self == "_"
  }
}
