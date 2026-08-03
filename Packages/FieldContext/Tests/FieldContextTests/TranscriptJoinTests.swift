@testable import FieldContext
import Testing

// MARK: - TranscriptJoinTests

struct TranscriptJoinTests {
  // MARK: Internal

  @Test func `an empty field starts A sentence with no separator`() {
    let join = TranscriptJoin(precedingText: "")
    #expect(join.needsLeadingSpace == false)
    #expect(join.capitalizesFirstCharacter)
    #expect(join.apply(to: "hello there") == "Hello there")
  }

  @Test func `consecutive dictations get one separating space`() {
    #expect(join("and then we left", after: "We arrived at noon") == " and then we left")
  }

  @Test func `a sentence ending period capitalizes the next transcript`() {
    #expect(join("we left at six.", after: "We arrived at noon.") == " We left at six.")
  }

  @Test(arguments: [
    "Stop!",
    "Really?",
    "He shouted!?"
  ]) func `every sentence terminator capitalizes`(
    precedingText: String,
  ) {
    #expect(TranscriptJoin(precedingText: precedingText).capitalizesFirstCharacter)
  }

  @Test func `a caret mid word neither spaces nor capitalizes`() {
    // The user parked the caret inside "conc|" and dictates the rest of the word.
    let join = TranscriptJoin(precedingText: "The conc")
    #expect(join.needsLeadingSpace)
    #expect(join.capitalizesFirstCharacter == false)
  }

  @Test func `existing trailing whitespace is never doubled`() {
    #expect(join("hello", after: "We arrived ") == "hello")
    #expect(join("hello", after: "We arrived  ") == "hello")
  }

  @Test func `trailing whitespace still sees the sentence before it`() {
    #expect(join("we left.", after: "We arrived at noon. ") == "We left.")
  }

  @Test func `a newline separates without capitalizing`() {
    // Rule (b) reads the trimmed text, and a bare line break ends no sentence.
    let join = TranscriptJoin(precedingText: "- buy milk\n")
    #expect(join.needsLeadingSpace == false)
    #expect(join.capitalizesFirstCharacter == false)
  }

  @Test func `a newline after A sentence still capitalizes`() {
    #expect(join("we left.", after: "We arrived at noon.\n") == "We left.")
  }

  @Test(arguments: ["He said \"", "See (", "The list [", "A set {", "She said “"])
  func `opening punctuation takes no separator`(precedingText: String) {
    #expect(TranscriptJoin(precedingText: precedingText).needsLeadingSpace == false)
  }

  @Test func `a straight quote is read from what precedes it`() {
    #expect(TranscriptJoin(precedingText: "He said \"").needsLeadingSpace == false)
    #expect(TranscriptJoin(precedingText: "He said \"hello\"").needsLeadingSpace)
    #expect(TranscriptJoin(precedingText: "He said '").needsLeadingSpace == false)
    #expect(TranscriptJoin(precedingText: "He said 'hello'").needsLeadingSpace)
    #expect(TranscriptJoin(precedingText: "(\"").needsLeadingSpace == false)
  }

  @Test func `a truncated window cannot be counted for quotes`() {
    // The opening quote fell off the front of the window; counting would call this one an opener
    // and glue the transcript to a closing quote.
    let truncated = TranscriptJoin(precedingText: "a quotation ends here\"", wasTruncated: true)
    #expect(truncated.needsLeadingSpace)
  }

  @Test func `a quote at the very start of A truncated window is assumed closing`() {
    #expect(TranscriptJoin(precedingText: "\"", wasTruncated: true).needsLeadingSpace)
    #expect(TranscriptJoin(precedingText: "\"", wasTruncated: false).needsLeadingSpace == false)
  }

  @Test func `an empty but truncated window separates without capitalizing`() {
    let join = TranscriptJoin(precedingText: "", wasTruncated: true)
    #expect(join.needsLeadingSpace)
    #expect(join.capitalizesFirstCharacter == false)
  }

  @Test(arguments: ["Section 3", "in 2026", "row 7"])
  func `digits before the caret separate without capitalizing`(precedingText: String) {
    let join = TranscriptJoin(precedingText: precedingText)
    #expect(join.needsLeadingSpace)
    #expect(join.capitalizesFirstCharacter == false)
  }

  @Test(arguments: ["we arrived,", "the plan:", "first;", "a thought —", "a range -"])
  func `non terminating punctuation separates without capitalizing`(precedingText: String) {
    let join = TranscriptJoin(precedingText: precedingText)
    #expect(join.needsLeadingSpace)
    #expect(join.capitalizesFirstCharacter == false)
  }

  @Test func `a closing paren without A terminator does not capitalize`() {
    let join = TranscriptJoin(precedingText: "We arrived (early)")
    #expect(join.needsLeadingSpace)
    #expect(join.capitalizesFirstCharacter == false)
  }

  @Test func `an opening quote after A sentence still capitalizes`() {
    #expect(join("get out.", after: "He turned. \"") == "Get out.")
  }

  @Test func `an opening quote mid sentence does not capitalize`() {
    #expect(join("get out", after: "He said \"") == "get out")
  }

  @Test func `a closing quote after A sentence capitalizes`() {
    #expect(join("she left.", after: "\"Get out.\"") == " She left.")
  }

  @Test func `a closing parenthesis inherits the sentence inside it`() {
    #expect(join("we left.", after: "(We arrived at noon.)") == " We left.")
    #expect(join("at noon", after: "We arrived (early)") == " at noon")
  }

  @Test(arguments: ["I was thinking…", "I was thinking...", "I was thinking… "])
  func `an ellipsis trails off without capitalizing`(precedingText: String) {
    #expect(TranscriptJoin(precedingText: precedingText).capitalizesFirstCharacter == false)
  }

  @Test func `an apostrophe after A word is A closing mark and keeps its separator`() {
    #expect(join("books", after: "the students'") == " books")
  }

  @Test func `an opening single quote takes no separator`() {
    #expect(join("hello", after: "He said '") == "hello")
  }

  @Test func `engine casing survives beyond the first letter`() {
    #expect(join("iPhone and macOS.", after: "We shipped.") == " IPhone and macOS.")
    #expect(join("iPhone and macOS.", after: "We ship") == " iPhone and macOS.")
  }

  @Test func `an already capitalized transcript is left alone`() {
    #expect(join("Paris was cold.", after: "We left.") == " Paris was cold.")
  }

  @Test func `a transcript starting with whitespace adds no second space`() {
    #expect(join(" hello", after: "We arrived") == " hello")
  }

  @Test func `an empty transcript stays empty`() {
    #expect(join("", after: "We arrived.") == "")
  }

  @Test func `a field of only whitespace starts A sentence`() {
    let join = TranscriptJoin(precedingText: "   ")
    #expect(join.needsLeadingSpace == false)
    #expect(join.capitalizesFirstCharacter)
  }

  @Test func `a field of only an opening quote starts A sentence`() {
    #expect(join("hello", after: "\"") == "Hello")
  }

  // MARK: Private

  private func join(_ transcript: String, after precedingText: String) -> String {
    TranscriptJoin(precedingText: precedingText).apply(to: transcript)
  }
}

// MARK: - ContextCaptureJoinTests

struct ContextCaptureJoinTests {
  // MARK: Internal

  @Test func `a selection joins against the text before it`() {
    // The paste replaces "We arrived at noon." so only "Yesterday: " decides the join.
    let capture = ContextCapture.available(
      context(before: "Yesterday: ", selected: "We arrived at noon."),
    )
    #expect(capture.adjusted("we left at six.") == "we left at six.")
  }

  @Test func `a selection after A sentence is capitalized`() {
    let capture = ContextCapture.available(
      context(before: "We arrived at noon.", selected: " We left at six."),
    )
    #expect(capture.adjusted("we stayed the night.") == " We stayed the night.")
  }

  @Test func `an unavailable capture delivers the transcript untouched`() {
    let capture = ContextCapture.unavailable(.gridSemantics(bundleID: "com.mitchellh.ghostty"))
    #expect(capture.adjusted("hello there") == "hello there")
  }

  // MARK: Private

  private func context(before: String, selected: String) -> FocusedTextContext {
    FocusedTextContext(
      role: "AXTextArea", before: before, selected: selected, after: "",
      selectedRange: before.utf16.count ..< (before.utf16.count + selected.utf16.count),
      beforeWasTruncated: false, selectionWasTruncated: false, afterWasTruncated: false,
    )
  }
}

// MARK: - TerminalBundleIDTests

struct TerminalBundleIDTests {
  @Test func `known terminals are recognized`() {
    #expect(TerminalBundleIDs.contains("com.mitchellh.ghostty"))
    #expect(TerminalBundleIDs.contains("com.apple.Terminal"))
  }

  @Test func `other apps and missing identifiers are not`() {
    #expect(TerminalBundleIDs.contains("com.apple.TextEdit") == false)
    #expect(TerminalBundleIDs.contains(nil) == false)
  }
}
