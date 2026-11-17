import CoreGraphics
import Foundation

// MARK: - ScreenContext

/// What was on screen around the target when its dictation started: the text the cleanup pass
/// reads to recognise names and identifiers the user can see but the field does not contain.
///
/// It is read at the press, while the user is still speaking, so it describes the screen they were
/// looking at when they chose their words. Each source it can come from is kept apart, because the
/// two are not equally trustworthy: text read from the target itself is the text, while text
/// recognized in a screenshot is a guess at it.
///
/// `Codable` because History persists it beside the field context, so the benchmark harness can
/// replay a dictation with each source in turn.
public struct ScreenContext: Equatable, Codable, Sendable {
  // MARK: Lifecycle

  public init(windowTitle: String?, structured: StructuredText?, recognizedText: String?) {
    self.windowTitle = windowTitle
    self.structured = structured
    self.recognizedText = recognizedText
  }

  // MARK: Public

  public enum Source: String, Codable, Sendable {
    /// The tmux pane the target is, captured by its own server.
    case tmux
    /// The target window's Accessibility tree.
    case accessibility
  }

  /// Text read from the target rather than from its pixels, in reading order.
  public struct StructuredText: Equatable, Codable, Sendable {
    // MARK: Lifecycle

    public init(source: Source, text: String) {
      self.source = source
      self.text = text
    }

    // MARK: Public

    public let source: Source
    public let text: String
  }

  public let windowTitle: String?
  public let structured: StructuredText?
  /// What Vision recognized in a screenshot of the target's window; nil without Screen Recording.
  public let recognizedText: String?

  /// The text the cleanup prompt is given: read text whenever there is any, because recognition
  /// drops exactly the diacritics and punctuation identifiers are made of.
  public var visibleText: String? {
    structured?.text ?? recognizedText
  }
}

// MARK: - VisibleLine

/// One run of text on screen and where it is, in global screen points with a top-left origin —
/// the Accessibility API's coordinate space, which recognized text is converted into.
public struct VisibleLine: Equatable, Sendable {
  // MARK: Lifecycle

  public init(text: String, frame: CGRect) {
    self.text = text
    self.frame = frame
  }

  // MARK: Public

  public let text: String
  public let frame: CGRect
}

// MARK: - VisibleText

/// Turns the lines a source found into the bounded text the prompt carries. The lines arrive in
/// reading order; this decides only which of them are worth keeping.
public enum VisibleText {
  /// UTF-16 units of screen text a prompt carries, roughly 1,500 tokens: a terminal screen or a
  /// chat's last few messages, not a whole document.
  public static let budget = 6000

  /// Points below which a row of text cannot be read, and so is not being shown.
  public static let minimumRowHeight: CGFloat = 8

  /// Keeps the lines that are visible in `bounds` and not inside the focused field, which travels
  /// separately as field context. Over budget, the lines farthest from the field go first; with
  /// no field, the farthest from the bottom of the window, where chats and terminals put whatever
  /// is newest.
  public static func compose(
    _ lines: [VisibleLine], within bounds: CGRect, excluding focus: CGRect?, budget: Int = budget,
  ) -> String {
    var kept: [VisibleLine] = []
    for line in lines {
      // Icon fonts draw their glyphs from the private-use area, which names nothing.
      let text = String(String.UnicodeScalarView(
        line.text.unicodeScalars.filter { $0.properties.generalCategory != .privateUse },
      ))
      .trimmingCharacters(in: .whitespacesAndNewlines)
      // Chrome locates text scrolled out of its viewport with no height, pinned to the
      // viewport's edge — inside the window, and often right beside the field.
      guard !text.isEmpty, !line.frame.isEmpty, line.frame.intersects(bounds) else {
        continue
      }
      if let focus, focus.contains(CGPoint(x: line.frame.midX, y: line.frame.midY)) {
        continue
      }
      kept.append(VisibleLine(text: text, frame: line.frame))
    }

    let anchor = focus?.midY ?? bounds.maxY
    var total = kept.reduce(0) { $0 + $1.text.utf16.count + 1 }
    var dropped = [Bool](repeating: false, count: kept.count)
    for index in kept.indices.sorted(by: {
      abs(kept[$0].frame.midY - anchor) > abs(kept[$1].frame.midY - anchor)
    }) {
      guard total > budget + 1 else {
        break
      }
      total -= kept[index].text.utf16.count + 1
      dropped[index] = true
    }
    return kept.indices.filter { !dropped[$0] }.map { kept[$0].text }.joined(separator: "\n")
  }

  /// Joins the runs a web page hands over for each link, code span, and highlighted token: each
  /// starts on the row the one before it ends on, touching it, or wraps from there onto the rows
  /// below. An Accessibility run carries its own spacing, so runs join as they are drawn;
  /// recognized text does not, and would lose the space between two boxes Vision split a line
  /// into.
  public static func joiningRuns(_ lines: [VisibleLine]) -> [VisibleLine] {
    var runs: [VisibleLine] = []
    for line in lines {
      if let last = runs.last, !last.frame.isEmpty, !line.frame.isEmpty,
         abs(line.frame.minY - last.frame.minY) <= 2,
         abs(line.frame.minX - last.frame.maxX) <= 1
         || (line.frame.maxY > last.frame.maxY + 2 && line.frame.maxX >= last.frame.maxX - 1)
      {
        runs[runs.count - 1] = VisibleLine(
          text: last.text + line.text, frame: last.frame.union(line.frame),
        )
      } else {
        runs.append(line)
      }
    }
    return runs
  }

  /// Where each row of one element's multi-line text sits on screen, so `compose` can keep or
  /// trim them one at a time, or nil when its text is drawn somewhere the app will not say.
  ///
  /// A frame that holds its rows is their layout, unless `locate`, which asks the app where a
  /// UTF-16 range of the text really is, puts the first or last row outside it: the frame was
  /// clipped to a viewport. Otherwise each row is located, starting from the first one in
  /// `window` and stopping at the first one below it. The app answers rows scrolled out above its
  /// viewport with an empty box or one above the window, so that first row is found by halving.
  /// An app that locates none of the rows keeps the text in a proxy: VS Code's editor is a
  /// one-line box holding the whole file, which says nothing of which lines are in view.
  public static func rows(
    of text: String, in frame: CGRect, within window: CGRect, locate: (Range<Int>) -> CGRect?,
  ) -> [VisibleLine]? {
    guard frame.height >= minimumRowHeight else {
      return []
    }
    var rows = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map {
      (
        text: String($0),
        range: text.utf16.distance(from: text.startIndex, to: $0.startIndex)
          ..< text.utf16.distance(from: text.startIndex, to: $0.endIndex),
      )
    }
    // A trailing newline draws no row.
    while rows.count > 1, rows[rows.count - 1].text.allSatisfy(\.isWhitespace) {
      rows.removeLast()
    }
    let shown = rows.indices.filter { !rows[$0].text.allSatisfy(\.isWhitespace) }
    guard let first = shown.first, let last = shown.last else {
      return []
    }
    func box(_ index: Int) -> CGRect? {
      locate(rows[index].range).flatMap { $0.isEmpty ? nil : $0 }
    }

    let height = frame.height / CGFloat(rows.count)
    if height >= minimumRowHeight, rows.count == 1 || [first, last].allSatisfy({ index in
      locate(rows[index].range).map { !$0.isEmpty && frame.insetBy(dx: -1, dy: -1).contains($0) }
        ?? true
    }) {
      return rows.enumerated().map { index, row in
        VisibleLine(text: row.text, frame: CGRect(
          x: frame.minX, y: frame.minY + CGFloat(index) * height, width: frame.width,
          height: height,
        ))
      }
    }

    var low = 0
    var high = shown.count
    while low < high {
      let middle = (low + high) / 2
      if let found = box(shown[middle]), found.maxY >= window.minY {
        high = middle
      } else {
        low = middle + 1
      }
    }
    guard low < shown.count else {
      return box(last) == nil ? nil : []
    }
    var located: [VisibleLine] = []
    for index in shown[low...] {
      guard let found = box(index) else {
        continue
      }
      guard found.minY <= window.maxY else {
        break
      }
      located.append(VisibleLine(text: rows[index].text, frame: found))
    }
    return located
  }
}
