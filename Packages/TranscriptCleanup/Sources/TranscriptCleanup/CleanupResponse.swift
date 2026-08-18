import Foundation

// MARK: - CleanupResponseShaping

/// Conforms a completion at the edge. No prompt makes a model's compliance a protocol, so the
/// wrappers that survive one are stripped here — and only the obvious ones: anything cleverer
/// starts editing the speaker's own text.
public enum CleanupResponseShaping {
  // MARK: Public

  /// A model that returned far more than it was given wrote something instead of editing what it
  /// was handed. The slack is generous because punctuation and symbol expansion legitimately grow
  /// a short transcript.
  public static let runawayLengthMultiple = 4
  public static let runawayLengthSlack = 200

  public static func shape(_ raw: String) -> String {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    // Wrappers nest — a label around a fence around a quotation — so each pass peels one layer
    // and the loop stops as soon as a pass finds nothing left to peel.
    for _ in 0 ..< maximumWrapperDepth {
      var peeled = strippingReasoningTags(text).trimmingCharacters(in: .whitespacesAndNewlines)
      peeled = strippingCodeFence(peeled).trimmingCharacters(in: .whitespacesAndNewlines)
      peeled = strippingLeadingLabel(peeled).trimmingCharacters(in: .whitespacesAndNewlines)
      peeled = strippingQuotationWrapper(peeled).trimmingCharacters(in: .whitespacesAndNewlines)
      guard peeled != text else {
        return text
      }
      text = peeled
    }
    return text
  }

  /// The shaped text, or why it cannot be delivered.
  public static func conform(_ raw: String,
                             transcript: String) -> Result<String, DegenerateResponse>
  {
    let shaped = shape(raw)
    guard !shaped.isEmpty else {
      return .failure(.empty)
    }
    guard
      shaped.count <= transcript.count * runawayLengthMultiple + runawayLengthSlack
    else {
      return .failure(.runaway(cleanedLength: shaped.count, transcriptLength: transcript.count))
    }
    return .success(shaped)
  }

  // MARK: Private

  private static let maximumWrapperDepth = 4
  private static let reasoningTags = ["think", "thinking", "reasoning", "reflection"]
  private static let outputTags = ["answer", "output", "response", "text", "transcript"]
  private static let leadingLabels = [
    "cleaned transcript", "cleaned text", "edited transcript", "edited text", "transcript",
    "output", "result", "final text",
  ]

  /// Reasoning blocks are dropped whole; a wrapper the model put the answer inside is unwrapped.
  private static func strippingReasoningTags(_ text: String) -> String {
    var text = text
    for tag in reasoningTags {
      while let block = enclosedRange(of: tag, in: text) {
        text.removeSubrange(block.outer)
      }
    }
    for tag in outputTags {
      if let block = enclosedRange(of: tag, in: text),
         text[..<block.outer.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
         text[block.outer.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        text = String(text[block.inner])
      }
    }
    return text
  }

  private static func enclosedRange(
    of tag: String, in text: String,
  ) -> (outer: Range<String.Index>, inner: Range<String.Index>)? {
    guard let open = text.range(of: "<\(tag)>", options: .caseInsensitive),
          let close = text.range(
            of: "</\(tag)>", options: .caseInsensitive, range: open.upperBound ..< text.endIndex,
          )
    else {
      return nil
    }
    return (open.lowerBound ..< close.upperBound, open.upperBound ..< close.lowerBound)
  }

  /// Only a fence around the entire answer is a wrapper. A fence in the middle is dictated code.
  private static func strippingCodeFence(_ text: String) -> String {
    var lines = text.components(separatedBy: "\n")
    guard lines.count >= 2, lines[0].hasPrefix("```"), lines[lines.count - 1].hasPrefix("```"),
          !lines[0].dropFirst(3).contains("`")
    else {
      return text
    }
    lines.removeFirst()
    lines.removeLast()
    return lines.joined(separator: "\n")
  }

  private static func strippingLeadingLabel(_ text: String) -> String {
    guard let colon = text.firstIndex(of: ":") else {
      return text
    }
    let emphasis = CharacterSet(charactersIn: " \t*#-").union(.whitespacesAndNewlines)
    let label = text[..<colon].lowercased().trimmingCharacters(in: emphasis)
    guard leadingLabels.contains(where: { label == $0 || label == "here is the \($0)" }) else {
      return text
    }
    // A bold label closes its emphasis after the colon: `**Cleaned transcript:** text`.
    let remainder = text[text.index(after: colon)...]
    guard text.hasPrefix("*") else {
      return String(remainder)
    }
    return String(remainder.drop(while: { $0 == "*" }))
  }

  /// A wrapper is a pair of quotes around everything with no bare copy of that quote inside; a
  /// speaker who dictated a quotation keeps it.
  private static func strippingQuotationWrapper(_ text: String) -> String {
    let pairs: [(Character, Character)] = [("\"", "\""), ("'", "'"), ("“", "”"), ("‘", "’")]
    guard let first = text.first, let last = text.last, text.count >= 2,
          let pair = pairs.first(where: { $0.0 == first && $0.1 == last })
    else {
      return text
    }
    let inner = text.dropFirst().dropLast()
    guard !inner.contains(pair.0), !inner.contains(pair.1) else {
      return text
    }
    return String(inner)
  }
}
