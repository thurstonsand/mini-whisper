// MARK: - FocusedTextContext

/// Text surrounding the insertion point of the focused field, read immediately before delivery.
///
/// It is a best-effort snapshot of the frontmost application, not a promise about where the
/// transcript ends up: nothing prevents another application from taking the front between this
/// read and the paste that follows it.
///
/// Offsets are in the Accessibility API's UTF-16 coordinate system, never `Character` offsets.
/// `before` ends where the selection starts, `selected` is the text a paste replaces, and `after`
/// starts where the selection ends. Each slice comes from its own bounded range read; a payload
/// exists only when every slice succeeded, so there is no partial capture.
public struct FocusedTextContext: Equatable, Sendable {
  // MARK: Lifecycle

  public init(
    role: String, before: String, selected: String, after: String, selectedRange: Range<Int>,
    beforeWasTruncated: Bool, selectionWasTruncated: Bool, afterWasTruncated: Bool,
  ) {
    self.role = role
    self.before = before
    self.selected = selected
    self.after = after
    self.selectedRange = selectedRange
    self.beforeWasTruncated = beforeWasTruncated
    self.selectionWasTruncated = selectionWasTruncated
    self.afterWasTruncated = afterWasTruncated
  }

  // MARK: Public

  public var role: String
  public var before: String
  public var selected: String
  public var after: String
  public var selectedRange: Range<Int>
  public var beforeWasTruncated: Bool
  public var selectionWasTruncated: Bool
  public var afterWasTruncated: Bool
}

// MARK: - FocusedTextWindow

/// How much of the field a capture reads, in UTF-16 code units.
public enum FocusedTextWindow {
  /// Neighbouring text kept on each side of the selection.
  public static let neighbourhood = 256
  /// Ceiling on the replaced selection; longer selections report `selectionWasTruncated`.
  public static let selection = 1024
}

// MARK: - ContextCapture

public enum ContextCapture: Equatable, Sendable {
  case available(FocusedTextContext)
  case unavailable(ContextUnavailable)
}

// MARK: - ContextUnavailable

/// Why a delivery had to proceed blind. Raw `AXError` values survive only inside `axFailure`,
/// for diagnostics.
public enum ContextUnavailable: Error, Equatable, Sendable {
  case accessibilityPermissionMissing
  case noFocusedElement
  case nonTextElement(role: String?)
  case noTextRange(role: String?)
  case gridSemantics(bundleID: String?)
  case protectedField(role: String?)
  case axFailure(operation: ContextAXOperation, error: Int32)
  /// The whole capture ran out of its budget; delivery refuses to wait any longer.
  case timedOut(operation: ContextAXOperation)
}

// MARK: - ContextAXOperation

public enum ContextAXOperation: String, Equatable, Sendable {
  case focusedElement
  case role
  case subrole
  case children
  case characterCount
  case selectedRange
  case stringForRange
}

public extension ContextCapture {
  /// The transcript as it should be pasted: joined to the text before the insertion point when a
  /// capture succeeded, untouched when it did not.
  func adjusted(_ transcript: String) -> String {
    switch self {
    case let .available(context):
      TranscriptJoin(precedingText: context.before, wasTruncated: context.beforeWasTruncated).apply(
        to: transcript,
      )
    case .unavailable:
      transcript
    }
  }
}
