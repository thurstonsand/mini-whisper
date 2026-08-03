@testable import FieldContext
import Testing

// MARK: - FocusedTextPlanningTests

struct FocusedTextPlanningTests {
  // MARK: Internal

  @Test func `a caret at the start reads nothing before it`() throws {
    let plan = try plan(count: 100, location: 0).get()
    #expect(plan.before == TextRange(location: 0, length: 0))
    #expect(plan.selected == TextRange(location: 0, length: 0))
    #expect(plan.after == TextRange(location: 0, length: 100))
    #expect(plan.beforeWasTruncated == false)
    #expect(plan.afterWasTruncated == false)
  }

  @Test func `a caret at the end reads nothing after it`() throws {
    let plan = try plan(count: 100, location: 100).get()
    #expect(plan.before == TextRange(location: 0, length: 100))
    #expect(plan.after == TextRange(location: 100, length: 0))
  }

  @Test func `an empty field plans three empty reads`() throws {
    let plan = try plan(count: 0, location: 0).get()
    #expect(plan.before.length == 0)
    #expect(plan.selected.length == 0)
    #expect(plan.after.length == 0)
    #expect(plan.selectedRange == 0 ..< 0)
  }

  @Test func `the neighbourhood cap is exact at its boundary`() throws {
    let exact = try plan(count: 512, location: 256).get()
    #expect(exact.before == TextRange(location: 0, length: 256))
    #expect(exact.beforeWasTruncated == false)

    // One unit past the cap starts truncating, and a truncated edge reads one unit extra so a
    // split pair can be dropped without costing a real character.
    let truncated = try plan(count: 512, location: 257).get()
    #expect(truncated.before == TextRange(location: 0, length: 257))
    #expect(truncated.beforeWasTruncated)

    let deep = try plan(count: 1000, location: 500).get()
    #expect(deep.before == TextRange(location: 243, length: 257))
  }

  @Test func `the trailing neighbourhood truncates the same way`() throws {
    let exact = try plan(count: 256, location: 0).get()
    #expect(exact.after == TextRange(location: 0, length: 256))
    #expect(exact.afterWasTruncated == false)

    let truncated = try plan(count: 1000, location: 0).get()
    #expect(truncated.after == TextRange(location: 0, length: 257))
    #expect(truncated.afterWasTruncated)
  }

  @Test func `a selection is capped but its real range is reported`() throws {
    let plan = try plan(count: 5000, location: 1000, length: 2000).get()
    #expect(plan.selected == TextRange(location: 1000, length: 1025))
    #expect(plan.selectionWasTruncated)
    #expect(plan.selectedRange == 1000 ..< 3000)
    #expect(plan.after == TextRange(location: 3000, length: 257))
  }

  @Test func `a selection inside the cap is read whole`() throws {
    let plan = try plan(count: 5000, location: 10, length: 1024).get()
    #expect(plan.selected == TextRange(location: 10, length: 1024))
    #expect(plan.selectionWasTruncated == false)
  }

  @Test(arguments: [
    (-1, 0, 0), (10, -1, 0), (10, 0, -1), (10, 11, 0), (10, 5, 6), (0, 1, 0),
    (Int.max, Int.max, Int.max),
  ]) func `malformed numbers never reach arithmetic`(count: Int, location: Int, length: Int) {
    #expect(plan(count: count, location: location, length: length) == .failure(.malformedSelection))
  }

  @Test func `a selection ending exactly at the end is well formed`() throws {
    let plan = try plan(count: 10, location: 4, length: 6).get()
    #expect(plan.selectedRange == 4 ..< 10)
    #expect(plan.after.length == 0)
  }

  // MARK: Private

  private func plan(
    count: Int, location: Int, length: Int = 0,
  ) -> Result<FocusedTextPlan, FocusedTextPlanFailure> {
    FocusedTextPlan.plan(
      characterCount: count, selectionLocation: location, selectionLength: length,
    )
  }
}

// MARK: - FocusedTextAssemblyTests

struct FocusedTextAssemblyTests {
  // MARK: Internal

  @Test func `a well formed read becomes A payload`() throws {
    let plan = try plan(count: 20, location: 5, length: 3)
    let context = try plan.assemble(
      role: "AXTextArea", before: "12345", selected: "678", after: filler(12),
    )
    .get()
    #expect(context.before == "12345")
    #expect(context.selected == "678")
    #expect(context.after.utf16.count == 12)
    #expect(context.selectedRange == 5 ..< 8)
  }

  @Test func `a slice of the wrong length is not A partial capture`() throws {
    let plan = try plan(count: 20, location: 5)
    #expect(
      plan.assemble(role: "AXTextArea", before: "1234", selected: "", after: filler(15))
        == .failure(.lengthMismatch),
    )
  }

  @Test func `an emoji spanning the cut is counted in UTF 16`() throws {
    // "👍" is two UTF-16 units, so a five-unit window holds three letters and one emoji.
    let plan = try plan(count: 5, location: 5)
    let context = try plan.assemble(role: "AXTextArea", before: "abc👍", selected: "", after: "")
      .get()
    #expect(context.before == "abc👍")
  }

  @Test func `a truncated edge drops the half pair it over read`() throws {
    let plan = try plan(count: 1000, location: 500)
    let before = replacement + filler(256)
    let after = filler(256) + replacement
    let context = try plan.assemble(role: "AXTextArea", before: before, selected: "", after: after)
      .get()
    #expect(context.before == filler(256))
    #expect(context.after == filler(256))
    #expect(context.beforeWasTruncated)
    #expect(context.afterWasTruncated)
  }

  @Test func `a truncated edge that split nothing keeps its extra unit`() throws {
    let plan = try plan(count: 1000, location: 500)
    let context = try plan.assemble(
      role: "AXTextArea", before: filler(257), selected: "", after: filler(257),
    )
    .get()
    #expect(context.before.utf16.count == 257)
    #expect(context.after.utf16.count == 257)
  }

  @Test func `a split at the caret costs the whole capture`() throws {
    let plan = try plan(count: 20, location: 5, length: 3)
    #expect(
      plan.assemble(
        role: "AXTextArea", before: "1234" + replacement, selected: "678", after: filler(12),
      )
        == .failure(.splitBoundary),
    )
  }

  @Test func `a split at either selection edge costs the whole capture`() throws {
    let plan = try plan(count: 20, location: 5, length: 3)
    #expect(
      plan.assemble(
        role: "AXTextArea", before: "12345", selected: replacement + "78", after: filler(12),
      )
        == .failure(.splitBoundary),
    )
    #expect(
      plan.assemble(
        role: "AXTextArea", before: "12345", selected: "67" + replacement, after: filler(12),
      )
        == .failure(.splitBoundary),
    )
    #expect(
      plan.assemble(
        role: "AXTextArea", before: "12345", selected: "678", after: replacement + filler(11),
      )
        == .failure(.splitBoundary),
    )
  }

  @Test func `a truncated selection may drop its own trailing half pair`() throws {
    let plan = try plan(count: 5000, location: 0, length: 2000)
    let selected = filler(1024) + replacement
    let context = try plan.assemble(
      role: "AXTextArea", before: "", selected: selected, after: filler(257),
    )
    .get()
    #expect(context.selected.utf16.count == 1024)
    #expect(context.selectionWasTruncated)
  }

  @Test func `a replacement character away from A cut is left alone`() throws {
    let plan = try plan(count: 3, location: 3)
    let context = try plan.assemble(
      role: "AXTextArea", before: "a" + replacement + "b", selected: "", after: "",
    )
    .get()
    #expect(context.before == "a\u{FFFD}b")
  }

  // MARK: Private

  private let replacement = "\u{FFFD}"

  private func plan(count: Int, location: Int, length: Int = 0) throws -> FocusedTextPlan {
    try FocusedTextPlan.plan(
      characterCount: count, selectionLocation: location, selectionLength: length,
    )
    .get()
  }

  private func filler(_ count: Int) -> String {
    String(repeating: "a", count: count)
  }
}

// MARK: - FieldTargetPolicyTests

struct FieldTargetPolicyTests {
  @Test func `web areas and groups are containers`() {
    #expect(FieldTargetPolicy.isContainer(role: "AXWebArea"))
    #expect(FieldTargetPolicy.isContainer(role: "AXGroup"))
    #expect(FieldTargetPolicy.isContainer(role: "AXTextArea") == false)
  }

  @Test func `only plain text fields need their subrole read`() {
    #expect(FieldTargetPolicy.needsSubroleCheck(role: "AXTextField"))
    #expect(FieldTargetPolicy.needsSubroleCheck(role: "AXTextArea") == false)
  }

  @Test func `a secure field is recognized from either role or subrole`() {
    #expect(FieldTargetPolicy.isSecure(role: "AXSecureTextField", subrole: nil))
    #expect(FieldTargetPolicy.isSecure(role: "AXTextField", subrole: "AXSecureTextField"))
    #expect(FieldTargetPolicy.isSecure(role: "AXTextField", subrole: "AXSearchField") == false)
    #expect(FieldTargetPolicy.isSecure(role: "AXTextArea", subrole: nil) == false)
  }
}
