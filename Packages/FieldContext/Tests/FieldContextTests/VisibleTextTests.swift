import FieldContext
import Foundation
import Testing

// MARK: - VisibleTextTests

/// A 1,000 × 800 window at the origin, with rows 40 points tall.
struct VisibleTextTests {
  // MARK: Internal

  @Test func `the field's own text and anything outside the window are left out, in order`() {
    let lines = [
      row("Priyanka Raghunathan", y: 0),
      row("Ok. Can you open MW-212?", y: 40),
      row("Scrolled off the bottom", y: 900),
      row("Sounds good, I'll", y: 700),
      row("   ", y: 120),
      row("  #mini-whisper \n", y: 80),
    ]

    let text = VisibleText.compose(lines, within: window, excluding: field(y: 700))

    #expect(text == "Priyanka Raghunathan\nOk. Can you open MW-212?\n#mini-whisper")
  }

  @Test func `over budget, the lines farthest from the field go first, wherever they are`() {
    // The field sits mid-window, so the two rows kept are neither the first two nor the last two:
    // trimming from either end would keep a different pair.
    let lines = [
      row("aaaa", y: 0), row("bbbb", y: 120), row("cccc", y: 400), row("dddd", y: 760),
    ]

    let beside = CGRect(x: 650, y: 400, width: 300, height: 60)

    let text = VisibleText.compose(lines, within: window, excluding: beside, budget: 9)

    #expect(text == "bbbb\ncccc")
  }

  @Test func `a line with no height shows nothing, even pinned beside the field`() {
    let lines = [
      row("on screen", y: 0),
      VisibleLine(text: "scrolled out", frame: CGRect(x: 20, y: 700, width: 600, height: 0)),
    ]

    let text = VisibleText.compose(lines, within: window, excluding: field(y: 600), budget: 12)

    #expect(text == "on screen")
  }

  @Test func `touching runs on one row join as drawn, apart from a column beside them`() {
    // Chrome's runs for "PostgreSQL's MVCC transaction semantics", the last wrapping from the
    // margin, then a sidebar on the same row with a gap before it, then the next paragraph.
    let lines = [
      VisibleLine(text: "PostgreSQL", frame: CGRect(x: 75, y: 173, width: 79, height: 20)),
      VisibleLine(text: "'s ", frame: CGRect(x: 153, y: 173, width: 14, height: 20)),
      VisibleLine(text: "MVCC", frame: CGRect(x: 167, y: 173, width: 41, height: 20)),
      VisibleLine(text: " transaction", frame: CGRect(x: 75, y: 173, width: 727, height: 42)),
      VisibleLine(text: "In this article", frame: CGRect(x: 820, y: 173, width: 120, height: 20)),
      VisibleLine(text: "Next paragraph", frame: CGRect(x: 75, y: 240, width: 300, height: 20)),
      // A timestamp floated right comes first in the page, left of nothing it touches.
      VisibleLine(text: "3 min ago", frame: CGRect(x: 800, y: 300, width: 80, height: 20)),
      VisibleLine(text: "Message", frame: CGRect(x: 75, y: 300, width: 300, height: 20)),
    ]

    let text = VisibleText.compose(VisibleText.joiningRuns(lines), within: window, excluding: nil)

    #expect(
      text == "PostgreSQL's MVCC transaction\nIn this article\nNext paragraph\n3 min ago\nMessage",
    )
  }

  @Test func `icon-font glyphs are dropped from the text around them`() {
    let lines = [row("\u{EB99} \u{EA9B} Profiles.swift", y: 0), row("\u{E092}", y: 40)]

    let text = VisibleText.compose(lines, within: window, excluding: nil)

    #expect(text == "Profiles.swift")
  }

  @Test func `rows that fit their frame are spread over it, and a trailing newline draws none`() {
    let rows = VisibleText.rows(
      of: "first\nsecond", in: CGRect(x: 20, y: 100, width: 600, height: 40), within: window,
      locate: { range in
        CGRect(x: 20, y: range.lowerBound == 0 ? 100 : 120, width: 80, height: 20)
      },
    )
    let label = VisibleText.rows(
      of: "Done\n", in: CGRect(x: 20, y: 300, width: 100, height: 14), within: window,
      locate: { _ in nil },
    )

    #expect(rows == [
      VisibleLine(text: "first", frame: CGRect(x: 20, y: 100, width: 600, height: 20)),
      VisibleLine(text: "second", frame: CGRect(x: 20, y: 120, width: 600, height: 20)),
    ])
    #expect(label?.map(\.text) == ["Done"])
  }

  @Test func `a frame clipped to its viewport is not spread, even when the rows would fit it`() {
    // Four 18-point rows in a 40-point frame: the first has scrolled out above the viewport.
    let boxes: [Int: CGRect] = [
      0: CGRect(x: 20, y: 100, width: 600, height: 0),
      2: CGRect(x: 20, y: 100, width: 600, height: 18),
      4: CGRect(x: 20, y: 118, width: 600, height: 18),
      6: CGRect(x: 20, y: 136, width: 600, height: 18),
    ]

    let rows = VisibleText.rows(
      of: "a\nb\nc\nd", in: CGRect(x: 20, y: 100, width: 600, height: 40), within: window,
      locate: { boxes[$0.lowerBound] },
    )

    #expect(rows?.map(\.text) == ["b", "c", "d"])
    #expect(rows?.map(\.frame.minY) == [100, 118, 136])
  }

  @Test func `an element too short for one row shows nothing`() {
    let rows = VisibleText.rows(
      of: "scrolled\nout", in: CGRect(x: 20, y: 173, width: 600, height: 1), within: window,
      locate: { _ in CGRect(x: 20, y: 173, width: 600, height: 15) },
    )

    #expect(rows == [])
  }

  @Test func `a clipped element's rows are where the app locates them, up to the window's edge`() {
    // Five rows in a 30-point frame clipped at the viewport's bottom: the app places the first
    // above the viewport with no height, the next two in it, and the last two below the window.
    // The emoji is two UTF-16 units, so every later row starts one unit further on.
    let text = "above\n🙂 shown\nalso shown\nbelow\nfurther"
    var asked: [Range<Int>] = []
    let boxes: [Int: CGRect] = [
      0: CGRect(x: 20, y: 770, width: 600, height: 0),
      6: CGRect(x: 20, y: 770, width: 600, height: 15),
      15: CGRect(x: 20, y: 785, width: 600, height: 15),
      26: CGRect(x: 20, y: 801, width: 600, height: 15),
      32: CGRect(x: 20, y: 816, width: 600, height: 15),
    ]

    let rows = VisibleText.rows(
      of: text, in: CGRect(x: 20, y: 770, width: 600, height: 30), within: window,
      locate: { range in
        asked.append(range)
        return boxes[range.lowerBound]
      },
    )

    #expect(rows?.map(\.text) == ["🙂 shown", "also shown"])
    #expect(rows?.map(\.frame.minY) == [770, 785])
    #expect(asked.contains(6 ..< 14) && asked.contains(26 ..< 31))
    #expect(!asked.contains(32 ..< 39), "every row after the first below the window is lower still")
  }

  @Test func `text the app cannot locate is unplaced, but text below the window is not`() {
    // A whole document behind a one-line box, which the app answers with an empty rectangle.
    let proxy = VisibleText.rows(
      of: "aa\nbb\ncc\ndd\nee", in: CGRect(x: 100, y: 400, width: 800, height: 18), within: window,
      locate: { _ in CGRect(x: 0, y: 720, width: 0, height: 0) },
    )
    let below = VisibleText.rows(
      of: "aa\nbb\ncc\ndd\nee", in: CGRect(x: 100, y: 790, width: 800, height: 18), within: window,
      locate: { range in
        CGRect(x: 100, y: 900 + CGFloat(range.lowerBound), width: 800, height: 15)
      },
    )

    #expect(proxy == nil)
    #expect(below == [])
  }

  @Test func `without a field, the bottom of the window is what stays`() {
    let lines = [row("oldest", y: 0), row("older", y: 360), row("newest", y: 720)]

    let text = VisibleText.compose(lines, within: window, excluding: nil, budget: 12)

    #expect(text == "older\nnewest")
  }

  // MARK: Private

  private let window = CGRect(x: 0, y: 0, width: 1000, height: 800)

  private func row(_ text: String, y: CGFloat) -> VisibleLine {
    VisibleLine(text: text, frame: CGRect(x: 20, y: y, width: 600, height: 40))
  }

  private func field(y: CGFloat) -> CGRect {
    CGRect(x: 10, y: y - 10, width: 900, height: 60)
  }
}
