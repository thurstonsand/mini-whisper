import Testing

@testable import FieldContext

@Suite struct TranscriptJoinTests {
  private func join(_ transcript: String, after precedingText: String) -> String {
    TranscriptJoin(precedingText: precedingText).apply(to: transcript)
  }

  @Test func anEmptyFieldStartsASentenceWithNoSeparator() {
    let join = TranscriptJoin(precedingText: "")
    #expect(join.needsLeadingSpace == false)
    #expect(join.capitalizesFirstCharacter)
    #expect(join.apply(to: "hello there") == "Hello there")
  }

  @Test func consecutiveDictationsGetOneSeparatingSpace() {
    #expect(join("and then we left", after: "We arrived at noon") == " and then we left")
  }

  @Test func aSentenceEndingPeriodCapitalizesTheNextTranscript() {
    #expect(join("we left at six.", after: "We arrived at noon.") == " We left at six.")
  }

  @Test(arguments: ["Stop!", "Really?", "He shouted!?"]) func everySentenceTerminatorCapitalizes(
    precedingText: String
  ) { #expect(TranscriptJoin(precedingText: precedingText).capitalizesFirstCharacter) }

  @Test func aCaretMidWordNeitherSpacesNorCapitalizes() {
    // The user parked the caret inside "conc|" and dictates the rest of the word.
    let join = TranscriptJoin(precedingText: "The conc")
    #expect(join.needsLeadingSpace)
    #expect(join.capitalizesFirstCharacter == false)
  }

  @Test func existingTrailingWhitespaceIsNeverDoubled() {
    #expect(join("hello", after: "We arrived ") == "hello")
    #expect(join("hello", after: "We arrived  ") == "hello")
  }

  @Test func trailingWhitespaceStillSeesTheSentenceBeforeIt() {
    #expect(join("we left.", after: "We arrived at noon. ") == "We left.")
  }

  @Test func aNewlineSeparatesWithoutCapitalizing() {
    // Rule (b) reads the trimmed text, and a bare line break ends no sentence.
    let join = TranscriptJoin(precedingText: "- buy milk\n")
    #expect(join.needsLeadingSpace == false)
    #expect(join.capitalizesFirstCharacter == false)
  }

  @Test func aNewlineAfterASentenceStillCapitalizes() {
    #expect(join("we left.", after: "We arrived at noon.\n") == "We left.")
  }

  @Test(arguments: ["He said \"", "See (", "The list [", "A set {", "She said “"])
  func openingPunctuationTakesNoSeparator(precedingText: String) {
    #expect(TranscriptJoin(precedingText: precedingText).needsLeadingSpace == false)
  }

  @Test func aStraightQuoteIsReadFromWhatPrecedesIt() {
    #expect(TranscriptJoin(precedingText: "He said \"").needsLeadingSpace == false)
    #expect(TranscriptJoin(precedingText: "He said \"hello\"").needsLeadingSpace)
    #expect(TranscriptJoin(precedingText: "He said '").needsLeadingSpace == false)
    #expect(TranscriptJoin(precedingText: "He said 'hello'").needsLeadingSpace)
    #expect(TranscriptJoin(precedingText: "(\"").needsLeadingSpace == false)
  }

  @Test func aTruncatedWindowCannotBeCountedForQuotes() {
    // The opening quote fell off the front of the window; counting would call this one an opener
    // and glue the transcript to a closing quote.
    let truncated = TranscriptJoin(precedingText: "a quotation ends here\"", wasTruncated: true)
    #expect(truncated.needsLeadingSpace)
  }

  @Test func aQuoteAtTheVeryStartOfATruncatedWindowIsAssumedClosing() {
    #expect(TranscriptJoin(precedingText: "\"", wasTruncated: true).needsLeadingSpace)
    #expect(TranscriptJoin(precedingText: "\"", wasTruncated: false).needsLeadingSpace == false)
  }

  @Test func anEmptyButTruncatedWindowSeparatesWithoutCapitalizing() {
    let join = TranscriptJoin(precedingText: "", wasTruncated: true)
    #expect(join.needsLeadingSpace)
    #expect(join.capitalizesFirstCharacter == false)
  }

  @Test(arguments: ["Section 3", "in 2026", "row 7"])
  func digitsBeforeTheCaretSeparateWithoutCapitalizing(precedingText: String) {
    let join = TranscriptJoin(precedingText: precedingText)
    #expect(join.needsLeadingSpace)
    #expect(join.capitalizesFirstCharacter == false)
  }

  @Test(arguments: ["we arrived,", "the plan:", "first;", "a thought —", "a range -"])
  func nonTerminatingPunctuationSeparatesWithoutCapitalizing(precedingText: String) {
    let join = TranscriptJoin(precedingText: precedingText)
    #expect(join.needsLeadingSpace)
    #expect(join.capitalizesFirstCharacter == false)
  }

  @Test func aClosingParenWithoutATerminatorDoesNotCapitalize() {
    let join = TranscriptJoin(precedingText: "We arrived (early)")
    #expect(join.needsLeadingSpace)
    #expect(join.capitalizesFirstCharacter == false)
  }

  @Test func anOpeningQuoteAfterASentenceStillCapitalizes() {
    #expect(join("get out.", after: "He turned. \"") == "Get out.")
  }

  @Test func anOpeningQuoteMidSentenceDoesNotCapitalize() {
    #expect(join("get out", after: "He said \"") == "get out")
  }

  @Test func aClosingQuoteAfterASentenceCapitalizes() {
    #expect(join("she left.", after: "\"Get out.\"") == " She left.")
  }

  @Test func aClosingParenthesisInheritsTheSentenceInsideIt() {
    #expect(join("we left.", after: "(We arrived at noon.)") == " We left.")
    #expect(join("at noon", after: "We arrived (early)") == " at noon")
  }

  @Test(arguments: ["I was thinking…", "I was thinking...", "I was thinking… "])
  func anEllipsisTrailsOffWithoutCapitalizing(precedingText: String) {
    #expect(TranscriptJoin(precedingText: precedingText).capitalizesFirstCharacter == false)
  }

  @Test func anApostropheAfterAWordIsAClosingMarkAndKeepsItsSeparator() {
    #expect(join("books", after: "the students'") == " books")
  }

  @Test func anOpeningSingleQuoteTakesNoSeparator() {
    #expect(join("hello", after: "He said '") == "hello")
  }

  @Test func engineCasingSurvivesBeyondTheFirstLetter() {
    #expect(join("iPhone and macOS.", after: "We shipped.") == " IPhone and macOS.")
    #expect(join("iPhone and macOS.", after: "We ship") == " iPhone and macOS.")
  }

  @Test func anAlreadyCapitalizedTranscriptIsLeftAlone() {
    #expect(join("Paris was cold.", after: "We left.") == " Paris was cold.")
  }

  @Test func aTranscriptStartingWithWhitespaceAddsNoSecondSpace() {
    #expect(join(" hello", after: "We arrived") == " hello")
  }

  @Test func anEmptyTranscriptStaysEmpty() { #expect(join("", after: "We arrived.") == "") }

  @Test func aFieldOfOnlyWhitespaceStartsASentence() {
    let join = TranscriptJoin(precedingText: "   ")
    #expect(join.needsLeadingSpace == false)
    #expect(join.capitalizesFirstCharacter)
  }

  @Test func aFieldOfOnlyAnOpeningQuoteStartsASentence() {
    #expect(join("hello", after: "\"") == "Hello")
  }
}

@Suite struct ContextCaptureJoinTests {
  private func context(before: String, selected: String) -> FocusedTextContext {
    FocusedTextContext(
      role: "AXTextArea", before: before, selected: selected, after: "",
      selectedRange: before.utf16.count..<(before.utf16.count + selected.utf16.count),
      beforeWasTruncated: false, selectionWasTruncated: false, afterWasTruncated: false)
  }

  @Test func aSelectionJoinsAgainstTheTextBeforeIt() {
    // The paste replaces "We arrived at noon." so only "Yesterday: " decides the join.
    let capture = ContextCapture.available(
      context(before: "Yesterday: ", selected: "We arrived at noon."))
    #expect(capture.adjusted("we left at six.") == "we left at six.")
  }

  @Test func aSelectionAfterASentenceIsCapitalized() {
    let capture = ContextCapture.available(
      context(before: "We arrived at noon.", selected: " We left at six."))
    #expect(capture.adjusted("we stayed the night.") == " We stayed the night.")
  }

  @Test func anUnavailableCaptureDeliversTheTranscriptUntouched() {
    let capture = ContextCapture.unavailable(.gridSemantics(bundleID: "com.mitchellh.ghostty"))
    #expect(capture.adjusted("hello there") == "hello there")
  }
}

@Suite struct TerminalBundleIDTests {
  @Test func knownTerminalsAreRecognized() {
    #expect(TerminalBundleIDs.contains("com.mitchellh.ghostty"))
    #expect(TerminalBundleIDs.contains("com.apple.Terminal"))
  }

  @Test func otherAppsAndMissingIdentifiersAreNot() {
    #expect(TerminalBundleIDs.contains("com.apple.TextEdit") == false)
    #expect(TerminalBundleIDs.contains(nil) == false)
  }
}
