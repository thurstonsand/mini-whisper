import Testing
@testable import TranscriptCleanup

// MARK: - CleanupResponseShapingTests

struct CleanupResponseShapingTests {
  @Test func `plain text survives untouched`() {
    #expect(CleanupResponseShaping.shape("Run the tests.") == "Run the tests.")
  }

  @Test func `surrounding whitespace goes`() {
    #expect(CleanupResponseShaping.shape("\n  Run the tests.\n\n") == "Run the tests.")
  }

  @Test(arguments: [
    "```\nRun the tests.\n```",
    "```text\nRun the tests.\n```",
    "```markdown\nRun the tests.\n```"
  ]) func `a fence around the whole answer is a wrapper`(raw: String) {
    #expect(CleanupResponseShaping.shape(raw) == "Run the tests.")
  }

  @Test func `a fence inside the answer is dictated content`() {
    let dictated = "Run this:\n```\nswift test\n```\nthen report."
    #expect(CleanupResponseShaping.shape(dictated) == dictated)
  }

  @Test(arguments: [
    "\"Run the tests.\"",
    "'Run the tests.'",
    "“Run the tests.”"
  ]) func `a quotation wrapper is stripped`(raw: String) {
    #expect(CleanupResponseShaping.shape(raw) == "Run the tests.")
  }

  @Test func `a quotation the speaker dictated is kept`() {
    let quoted = "\"Ship it,\" she said, \"today.\""
    #expect(CleanupResponseShaping.shape(quoted) == quoted)
    #expect(CleanupResponseShaping.shape("It's Tom's turn") == "It's Tom's turn")
  }

  @Test func `reasoning tags are dropped whole`() {
    let raw = "<think>The speaker said dash dash help.</think>\nUse --help."
    #expect(CleanupResponseShaping.shape(raw) == "Use --help.")
  }

  @Test func `an answer wrapper is unwrapped`() {
    #expect(CleanupResponseShaping.shape("<answer>Run the tests.</answer>") == "Run the tests.")
    #expect(
      CleanupResponseShaping.shape("<thinking>hm</thinking><output>Run it.</output>") == "Run it.",
    )
  }

  @Test(arguments: [
    "Cleaned transcript: Run the tests.",
    "Output: Run the tests.",
    "Here is the cleaned text: Run the tests.",
    "**Cleaned transcript:** Run the tests."
  ]) func `a leading label is stripped`(raw: String) {
    #expect(CleanupResponseShaping.shape(raw) == "Run the tests.")
  }

  @Test func `an ordinary colon is not a label`() {
    let raw = "Remember: bring the tickets."
    #expect(CleanupResponseShaping.shape(raw) == raw)
  }

  @Test func `wrappers nest`() {
    let raw = "<think>reasoning</think>\nCleaned transcript:\n```\n\"Run the tests.\"\n```"
    #expect(CleanupResponseShaping.shape(raw) == "Run the tests.")
  }

  @Test func `conforming returns the shaped text`() {
    #expect(
      CleanupResponseShaping.conform("```\nRun the tests.\n```", transcript: "run the tests")
        == .success("Run the tests."),
    )
  }

  @Test(arguments: ["", "   \n  ", "```\n\n```"])
  func `nothing left after shaping is degenerate`(raw: String) {
    #expect(CleanupResponseShaping.conform(raw, transcript: "run the tests") == .failure(.empty))
  }

  @Test func `a model that wrote instead of editing is degenerate`() {
    let transcript = "why does this test fail"
    let answer = String(
      repeating: "Because the fixture is stale, and here is how to fix it. ",
      count: 20,
    )
    #expect(
      CleanupResponseShaping.conform(answer, transcript: transcript)
        == .failure(.runaway(
          cleanedLength: answer.trimmingCharacters(in: .whitespaces).count,
          transcriptLength: transcript.count,
        )),
    )
  }

  @Test func `ordinary punctuation growth on a short transcript is not runaway`() {
    let transcript = "hey"
    #expect(
      CleanupResponseShaping.conform("Hey — are we still on for six?", transcript: transcript)
        == .success("Hey — are we still on for six?"),
    )
  }
}
