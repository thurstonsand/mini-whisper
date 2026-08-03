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

  @Test(arguments: ["we arrived,", "the plan:", "first;", "a thought —", "a range -"])
  func `a continuation lowercases the engine's opening capital`(precedingText: String) {
    // Parakeet capitalizes the first word of every utterance; mid-sentence it is wrong.
    #expect(join("Will it act differently?", after: precedingText)
      .hasSuffix("will it act differently?"))
  }

  @Test func `inherited trailing whitespace still lowercases`() {
    #expect(join("Will it act differently?", after: "comma, ") == "will it act differently?")
  }

  @Test func `a mid word caret lowercases the engine capital`() {
    #expect(join("Crete", after: "The con") == " crete")
  }

  @Test func `a closing paren and an ellipsis lowercase too`() {
    #expect(join("Then we left", after: "We arrived (early)") == " then we left")
    #expect(join("Then we left", after: "I was thinking…") == " then we left")
  }

  @Test func `a sentence start still capitalizes rather than lowercasing`() {
    #expect(join("Will it act differently?", after: "We arrived.") == " Will it act differently?")
    #expect(join("Will it act differently?", after: "") == "Will it act differently?")
  }

  @Test(arguments: [
    "I",
    "I'm late",
    "I'll go",
    "I've seen it",
    "I'd rather not",
    "I was there",
    "I’m late",
    "I, for one"
  ])
  func `the first person I keeps its capital mid sentence`(transcript: String) {
    #expect(join(transcript, after: "we arrived,") == " \(transcript)")
  }

  @Test(arguments: ["\"Will it work?\"", "(Will it work?)", "“Will it work?”", " Will it work?"])
  func `the engine capital is found behind opening punctuation and space`(transcript: String) {
    // The capital the engine wrote is not always at index 0, so the first letter is what moves.
    let joined = join(transcript, after: "we arrived,")
    #expect(joined.contains("will it work?"))
    #expect(joined.contains("Will") == false)
  }

  @Test func `a sentence start reaches the same letter behind punctuation`() {
    #expect(join("\"will it work?\"", after: "We arrived.") == " \"Will it work?\"")
    #expect(join(" will it work?", after: "We arrived.") == " Will it work?")
  }

  @Test func `a titlecase letter is re cased by its mapping`() {
    // U+01C5 (ǅ) is titlecase: neither isUppercase nor isLowercase answers for it, but its case
    // mappings do — down to U+01C6, up to U+01C4.
    #expect(join("\u{01C5}ena", after: "we saw,") == " \u{01C6}ena")
    #expect(join("\u{01C5}ena", after: "We saw.") == " \u{01C4}ena")
  }

  @Test func `a multi scalar case mapping is spliced in whole`() {
    // "ẞ".lowercased() is one scalar, but "ß".uppercased() is two — the replacement is a string.
    #expect(join("ßtrasse", after: "We arrived.") == " SStrasse")
    #expect(join("ẞtrasse", after: "we arrived,") == " ßtrasse")
  }

  @Test func `a transcript that opens with A digit is left alone`() {
    #expect(join("42 Dogs barked", after: "we counted,") == " 42 Dogs barked")
    #expect(join("42 dogs barked", after: "We counted.") == " 42 dogs barked")
  }

  @Test func `the first person rule is applied at the letter not at index zero`() {
    #expect(join("\"I'm late\"", after: "we arrived,") == " \"I'm late\"")
    #expect(join("(I was there)", after: "we arrived,") == " (I was there)")
    #expect(join("\"Italy was cold\"", after: "we arrived,") == " \"italy was cold\"")
  }

  @Test func `a proper noun mid sentence is lowercased and that cost is accepted`() {
    // Only the pronoun I is worth an exception; a name after a comma loses its capital rather
    // than every dictation keeping a wrong one.
    #expect(join("Italy was cold", after: "we arrived,") == " italy was cold")
    #expect(join("Paris was cold", after: "we arrived,") == " paris was cold")
  }

  @Test func `casing beyond the first letter is never touched by lowercasing`() {
    #expect(join("MacOS and iPhone", after: "we shipped,") == " macOS and iPhone")
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

  @Test func `a selection that swallowed the space before it still separates`() {
    // As reported from live use: the selection starts at the space after the comma, so the text
    // before it ends at the comma and the join owes a separator.
    let capture = ContextCapture.available(
      context(before: "select a sentence,", selected: " asdf asdf asdf"),
    )
    #expect(capture.adjusted("Will it act differently?") == " will it act differently?")
  }

  @Test func `a selection that left the space behind adds no second one`() {
    // The layout the live probe measured in Dia for the same field with a word-wise selection:
    // AXSelectedTextRange {19, 15}, which puts the space in `before` and the trailing one inside
    // the selection. Only `before` decides, and it already ends in whitespace.
    let capture = ContextCapture.available(
      context(before: "select a sentence, ", selected: "asdf asdf asdf "),
    )
    #expect(capture.adjusted("Will it act differently?") == "will it act differently?")
  }

  @Test func `an unavailable capture delivers the transcript untouched`() {
    let capture = ContextCapture.unavailable(.gridSemantics(bundleID: "com.mitchellh.ghostty"))
    #expect(capture.adjusted("hello there") == "hello there")
  }

  @Test func `a google docs keystroke sink is recognized`() {
    // Measured 2026-08-02: the focused AXTextArea inside Docs answers two zero-width spaces with
    // the caret at index 1, whatever the document holds.
    let sink = context(before: "\u{200B}", selected: "", after: "\u{200B}")
    #expect(sink.isZeroWidthSink)
    // Joining against it would invent a preceding word character and add a space.
    #expect(ContextCapture.available(sink).adjusted("Hello") == " hello")
  }

  @Test func `a truncated window of zero width characters is not A sink`() {
    // A window that hit its cap is a slice of something larger; the Docs signature is a whole,
    // untruncated field holding nothing but the sink.
    var truncatedBefore = context(before: "\u{200B}", selected: "", after: "\u{200B}")
    truncatedBefore.beforeWasTruncated = true
    #expect(truncatedBefore.isZeroWidthSink == false)
    var truncatedAfter = context(before: "\u{200B}", selected: "", after: "\u{200B}")
    truncatedAfter.afterWasTruncated = true
    #expect(truncatedAfter.isZeroWidthSink == false)
  }

  @Test func `a real field is not A sink`() {
    #expect(context(before: "We arrived.", selected: "", after: "").isZeroWidthSink == false)
    #expect(context(before: "\u{200B}We arrived", selected: "", after: "").isZeroWidthSink == false)
    // An empty field has no sink to report; it is simply empty.
    #expect(context(before: "", selected: "", after: "").isZeroWidthSink == false)
    #expect(context(before: " ", selected: "", after: "").isZeroWidthSink == false)
  }

  // MARK: Private

  private func context(
    before: String, selected: String, after: String = "",
  ) -> FocusedTextContext {
    FocusedTextContext(
      role: "AXTextArea", before: before, selected: selected, after: after,
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
