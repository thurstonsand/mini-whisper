public struct TextRange: Equatable, Sendable {
  public var location: Int
  public var length: Int

  public init(location: Int, length: Int) {
    self.location = location
    self.length = length
  }
}

public enum FocusedTextPlanFailure: Error, Equatable, Sendable {
  /// The target reported a character count or selection that cannot describe a document.
  case malformedSelection
  /// A bounded range came back with the wrong amount of text.
  case lengthMismatch
  /// A slice boundary landed inside a surrogate pair, so the text on one side is corrupt.
  case splitBoundary
}

/// Turns a target's reported character count and selection into the three range reads a capture
/// performs, then assembles their answers into a payload.
///
/// The planning half is arithmetic over untrusted numbers and the assembly half is arithmetic over
/// untrusted text, so both live here rather than in the Accessibility call layer.
public struct FocusedTextPlan: Equatable, Sendable {
  public let before: TextRange
  public let selected: TextRange
  public let after: TextRange
  public let selectedRange: Range<Int>
  public let beforeWasTruncated: Bool
  public let selectionWasTruncated: Bool
  public let afterWasTruncated: Bool

  /// The replacement character a target substitutes for half of a surrogate pair.
  private static let replacement: Character = "\u{FFFD}"

  /// Truncated edges read one unit past their cap so a split pair can be dropped without spending
  /// the budget: the extra unit is the one that goes, not a real character.
  private static let boundaryOverRead = 1

  public static func plan(
    characterCount: Int, selectionLocation: Int, selectionLength: Int
  ) -> Result<FocusedTextPlan, FocusedTextPlanFailure> {
    guard characterCount >= 0, selectionLocation >= 0, selectionLength >= 0,
      selectionLocation <= characterCount, selectionLength <= characterCount - selectionLocation
    else { return .failure(.malformedSelection) }

    let selectionEnd = selectionLocation + selectionLength
    let beforeWasTruncated = selectionLocation > FocusedTextWindow.neighbourhood
    let selectionWasTruncated = selectionLength > FocusedTextWindow.selection
    let afterAvailable = characterCount - selectionEnd
    let afterWasTruncated = afterAvailable > FocusedTextWindow.neighbourhood

    let beforeLength =
      min(selectionLocation, FocusedTextWindow.neighbourhood)
      + (beforeWasTruncated ? boundaryOverRead : 0)
    let selectedLength =
      min(selectionLength, FocusedTextWindow.selection)
      + (selectionWasTruncated ? boundaryOverRead : 0)
    let afterLength =
      min(afterAvailable, FocusedTextWindow.neighbourhood)
      + (afterWasTruncated ? boundaryOverRead : 0)

    return .success(
      FocusedTextPlan(
        before: TextRange(location: selectionLocation - beforeLength, length: beforeLength),
        selected: TextRange(location: selectionLocation, length: selectedLength),
        after: TextRange(location: selectionEnd, length: afterLength),
        selectedRange: selectionLocation..<selectionEnd, beforeWasTruncated: beforeWasTruncated,
        selectionWasTruncated: selectionWasTruncated, afterWasTruncated: afterWasTruncated))
  }

  public func assemble(
    role: String, before: String, selected: String, after: String
  ) -> Result<FocusedTextContext, FocusedTextPlanFailure> {
    let slices = [(before, self.before), (selected, self.selected), (after, self.after)]
    guard slices.allSatisfy({ $0.0.utf16.count == $0.1.length }) else {
      return .failure(.lengthMismatch)
    }

    // The cuts the target made at the selection's own edges cannot be repaired by reading more, so
    // a pair split there costs the whole capture.
    guard before.last != Self.replacement, selected.first != Self.replacement,
      after.first != Self.replacement, selectionWasTruncated || selected.last != Self.replacement
    else { return .failure(.splitBoundary) }

    return .success(
      FocusedTextContext(
        role: role, before: trimmed(before, leading: beforeWasTruncated),
        selected: trimmed(selected, trailing: selectionWasTruncated),
        after: trimmed(after, trailing: afterWasTruncated), selectedRange: selectedRange,
        beforeWasTruncated: beforeWasTruncated, selectionWasTruncated: selectionWasTruncated,
        afterWasTruncated: afterWasTruncated))
  }

  private func trimmed(_ text: String, leading: Bool = false, trailing: Bool = false) -> String {
    var trimmed = Substring(text)
    if leading, trimmed.first == Self.replacement { trimmed = trimmed.dropFirst() }
    if trailing, trimmed.last == Self.replacement { trimmed = trimmed.dropLast() }
    return String(trimmed)
  }
}
