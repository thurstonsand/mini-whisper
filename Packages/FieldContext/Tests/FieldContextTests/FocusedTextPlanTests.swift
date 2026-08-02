import Testing

@testable import FieldContext

@Suite struct FocusedTextPlanningTests {
  private func plan(
    count: Int, location: Int, length: Int = 0
  ) -> Result<FocusedTextPlan, FocusedTextPlanFailure> {
    FocusedTextPlan.plan(
      characterCount: count, selectionLocation: location, selectionLength: length)
  }

  @Test func aCaretAtTheStartReadsNothingBeforeIt() throws {
    let plan = try plan(count: 100, location: 0).get()
    #expect(plan.before == TextRange(location: 0, length: 0))
    #expect(plan.selected == TextRange(location: 0, length: 0))
    #expect(plan.after == TextRange(location: 0, length: 100))
    #expect(plan.beforeWasTruncated == false)
    #expect(plan.afterWasTruncated == false)
  }

  @Test func aCaretAtTheEndReadsNothingAfterIt() throws {
    let plan = try plan(count: 100, location: 100).get()
    #expect(plan.before == TextRange(location: 0, length: 100))
    #expect(plan.after == TextRange(location: 100, length: 0))
  }

  @Test func anEmptyFieldPlansThreeEmptyReads() throws {
    let plan = try plan(count: 0, location: 0).get()
    #expect(plan.before.length == 0)
    #expect(plan.selected.length == 0)
    #expect(plan.after.length == 0)
    #expect(plan.selectedRange == 0..<0)
  }

  @Test func theNeighbourhoodCapIsExactAtItsBoundary() throws {
    let exact = try plan(count: 512, location: 256).get()
    #expect(exact.before == TextRange(location: 0, length: 256))
    #expect(exact.beforeWasTruncated == false)

    // One unit past the cap starts truncating, and a truncated edge reads one unit extra so a
    // split pair can be dropped without costing a real character.
    let truncated = try plan(count: 512, location: 257).get()
    #expect(truncated.before == TextRange(location: 0, length: 257))
    #expect(truncated.beforeWasTruncated)

    let deep = try plan(count: 1_000, location: 500).get()
    #expect(deep.before == TextRange(location: 243, length: 257))
  }

  @Test func theTrailingNeighbourhoodTruncatesTheSameWay() throws {
    let exact = try plan(count: 256, location: 0).get()
    #expect(exact.after == TextRange(location: 0, length: 256))
    #expect(exact.afterWasTruncated == false)

    let truncated = try plan(count: 1_000, location: 0).get()
    #expect(truncated.after == TextRange(location: 0, length: 257))
    #expect(truncated.afterWasTruncated)
  }

  @Test func aSelectionIsCappedButItsRealRangeIsReported() throws {
    let plan = try plan(count: 5_000, location: 1_000, length: 2_000).get()
    #expect(plan.selected == TextRange(location: 1_000, length: 1_025))
    #expect(plan.selectionWasTruncated)
    #expect(plan.selectedRange == 1_000..<3_000)
    #expect(plan.after == TextRange(location: 3_000, length: 257))
  }

  @Test func aSelectionInsideTheCapIsReadWhole() throws {
    let plan = try plan(count: 5_000, location: 10, length: 1_024).get()
    #expect(plan.selected == TextRange(location: 10, length: 1_024))
    #expect(plan.selectionWasTruncated == false)
  }

  @Test(arguments: [
    (-1, 0, 0), (10, -1, 0), (10, 0, -1), (10, 11, 0), (10, 5, 6), (0, 1, 0),
    (Int.max, Int.max, Int.max),
  ]) func malformedNumbersNeverReachArithmetic(count: Int, location: Int, length: Int) {
    #expect(plan(count: count, location: location, length: length) == .failure(.malformedSelection))
  }

  @Test func aSelectionEndingExactlyAtTheEndIsWellFormed() throws {
    let plan = try plan(count: 10, location: 4, length: 6).get()
    #expect(plan.selectedRange == 4..<10)
    #expect(plan.after.length == 0)
  }
}

@Suite struct FocusedTextAssemblyTests {
  private let replacement = "\u{FFFD}"

  private func plan(count: Int, location: Int, length: Int = 0) throws -> FocusedTextPlan {
    try FocusedTextPlan.plan(
      characterCount: count, selectionLocation: location, selectionLength: length
    ).get()
  }

  private func filler(_ count: Int) -> String { String(repeating: "a", count: count) }

  @Test func aWellFormedReadBecomesAPayload() throws {
    let plan = try plan(count: 20, location: 5, length: 3)
    let context = try plan.assemble(
      role: "AXTextArea", before: "12345", selected: "678", after: filler(12)
    ).get()
    #expect(context.before == "12345")
    #expect(context.selected == "678")
    #expect(context.after.utf16.count == 12)
    #expect(context.selectedRange == 5..<8)
  }

  @Test func aSliceOfTheWrongLengthIsNotAPartialCapture() throws {
    let plan = try plan(count: 20, location: 5)
    #expect(
      plan.assemble(role: "AXTextArea", before: "1234", selected: "", after: filler(15))
        == .failure(.lengthMismatch))
  }

  @Test func anEmojiSpanningTheCutIsCountedInUTF16() throws {
    // "👍" is two UTF-16 units, so a five-unit window holds three letters and one emoji.
    let plan = try plan(count: 5, location: 5)
    let context = try plan.assemble(role: "AXTextArea", before: "abc👍", selected: "", after: "")
      .get()
    #expect(context.before == "abc👍")
  }

  @Test func aTruncatedEdgeDropsTheHalfPairItOverRead() throws {
    let plan = try plan(count: 1_000, location: 500)
    let before = replacement + filler(256)
    let after = filler(256) + replacement
    let context = try plan.assemble(role: "AXTextArea", before: before, selected: "", after: after)
      .get()
    #expect(context.before == filler(256))
    #expect(context.after == filler(256))
    #expect(context.beforeWasTruncated)
    #expect(context.afterWasTruncated)
  }

  @Test func aTruncatedEdgeThatSplitNothingKeepsItsExtraUnit() throws {
    let plan = try plan(count: 1_000, location: 500)
    let context = try plan.assemble(
      role: "AXTextArea", before: filler(257), selected: "", after: filler(257)
    ).get()
    #expect(context.before.utf16.count == 257)
    #expect(context.after.utf16.count == 257)
  }

  @Test func aSplitAtTheCaretCostsTheWholeCapture() throws {
    let plan = try plan(count: 20, location: 5, length: 3)
    #expect(
      plan.assemble(
        role: "AXTextArea", before: "1234" + replacement, selected: "678", after: filler(12))
        == .failure(.splitBoundary))
  }

  @Test func aSplitAtEitherSelectionEdgeCostsTheWholeCapture() throws {
    let plan = try plan(count: 20, location: 5, length: 3)
    #expect(
      plan.assemble(
        role: "AXTextArea", before: "12345", selected: replacement + "78", after: filler(12))
        == .failure(.splitBoundary))
    #expect(
      plan.assemble(
        role: "AXTextArea", before: "12345", selected: "67" + replacement, after: filler(12))
        == .failure(.splitBoundary))
    #expect(
      plan.assemble(
        role: "AXTextArea", before: "12345", selected: "678", after: replacement + filler(11))
        == .failure(.splitBoundary))
  }

  @Test func aTruncatedSelectionMayDropItsOwnTrailingHalfPair() throws {
    let plan = try plan(count: 5_000, location: 0, length: 2_000)
    let selected = filler(1_024) + replacement
    let context = try plan.assemble(
      role: "AXTextArea", before: "", selected: selected, after: filler(257)
    ).get()
    #expect(context.selected.utf16.count == 1_024)
    #expect(context.selectionWasTruncated)
  }

  @Test func aReplacementCharacterAwayFromACutIsLeftAlone() throws {
    let plan = try plan(count: 3, location: 3)
    let context = try plan.assemble(
      role: "AXTextArea", before: "a" + replacement + "b", selected: "", after: ""
    ).get()
    #expect(context.before == "a\u{FFFD}b")
  }
}

@Suite struct FieldTargetPolicyTests {
  @Test func webAreasAndGroupsAreContainers() {
    #expect(FieldTargetPolicy.isContainer(role: "AXWebArea"))
    #expect(FieldTargetPolicy.isContainer(role: "AXGroup"))
    #expect(FieldTargetPolicy.isContainer(role: "AXTextArea") == false)
  }

  @Test func onlyPlainTextFieldsNeedTheirSubroleRead() {
    #expect(FieldTargetPolicy.needsSubroleCheck(role: "AXTextField"))
    #expect(FieldTargetPolicy.needsSubroleCheck(role: "AXTextArea") == false)
  }

  @Test func aSecureFieldIsRecognizedFromEitherRoleOrSubrole() {
    #expect(FieldTargetPolicy.isSecure(role: "AXSecureTextField", subrole: nil))
    #expect(FieldTargetPolicy.isSecure(role: "AXTextField", subrole: "AXSecureTextField"))
    #expect(FieldTargetPolicy.isSecure(role: "AXTextField", subrole: "AXSearchField") == false)
    #expect(FieldTargetPolicy.isSecure(role: "AXTextArea", subrole: nil) == false)
  }
}
