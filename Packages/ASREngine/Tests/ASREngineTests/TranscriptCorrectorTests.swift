@testable import ASREngine
import Testing

struct TranscriptCorrectorTests {
  struct Case: CustomTestStringConvertible {
    let name: String
    let transcript: String
    let vocabulary: [String]
    let corrections: [TranscriptionCorrection]
    let expected: String

    var testDescription: String {
      name
    }
  }

  @Test(
    arguments: [
      Case(
        name: "empty dictionary is a no-op",
        transcript: "Mini whisper",
        vocabulary: [],
        corrections: [],
        expected: "Mini whisper",
      ),
      Case(
        name: "corrections ignore case",
        transcript: "MINI WHISPERER works",
        vocabulary: [],
        corrections: [.init(misspelling: "mini whisperer", text: "MiniWhisper")],
        expected: "MiniWhisper works",
      ),
      Case(
        name: "word boundaries reject substrings",
        transcript: "art is inside cartography",
        vocabulary: [],
        corrections: [.init(misspelling: "art", text: "craft")],
        expected: "Craft is inside cartography",
      ),
      Case(
        name: "phrases match",
        transcript: "use point free today",
        vocabulary: [],
        corrections: [.init(misspelling: "point free", text: "Point-Free")],
        expected: "use Point-Free today",
      ),
      Case(
        name: "longest overlap wins",
        transcript: "mini whisper app",
        vocabulary: [],
        corrections: [
          .init(misspelling: "mini whisper", text: "MiniWhisper"),
          .init(misspelling: "mini", text: "tiny"),
        ],
        expected: "MiniWhisper app",
      ),
      Case(
        name: "longest later-starting overlap wins",
        transcript: "mini whisper application",
        vocabulary: [],
        corrections: [
          .init(misspelling: "mini whisper", text: "MiniWhisper"),
          .init(misspelling: "whisper application", text: "product"),
        ],
        expected: "mini product",
      ),
      Case(
        name: "output is not rematched",
        transcript: "alpha beta",
        vocabulary: [],
        corrections: [
          .init(misspelling: "alpha", text: "beta"),
          .init(misspelling: "beta", text: "gamma"),
        ],
        expected: "Beta gamma",
      ),
      Case(
        name: "output is not case repaired",
        transcript: "mini whisperer",
        vocabulary: ["MINIWHISPER"],
        corrections: [.init(misspelling: "mini whisperer", text: "miniwhisper")],
        expected: "Miniwhisper",
      ),
      Case(
        name: "taught casing lands verbatim",
        transcript: "use MINI WHISPERER",
        vocabulary: [],
        corrections: [.init(misspelling: "mini whisperer", text: "miniWhisper")],
        expected: "use miniWhisper",
      ),
      Case(
        name: "lowercase taught form capitalizes at start",
        transcript: "MINI WHISPERER works",
        vocabulary: [],
        corrections: [.init(misspelling: "mini whisperer", text: "miniwhisper")],
        expected: "Miniwhisper works",
      ),
      Case(
        name: "lowercase taught form capitalizes after punctuation",
        transcript: "Done. mini whisperer works",
        vocabulary: [],
        corrections: [.init(misspelling: "mini whisperer", text: "miniwhisper")],
        expected: "Done. Miniwhisper works",
      ),
      Case(
        name: "lowercase taught form remains lowercase mid-sentence",
        transcript: "use MINI WHISPERER",
        vocabulary: [],
        corrections: [.init(misspelling: "mini whisperer", text: "miniwhisper")],
        expected: "use miniwhisper",
      ),
      Case(
        name: "mixed case remains at start",
        transcript: "mini whisperer works",
        vocabulary: [],
        corrections: [.init(misspelling: "mini whisperer", text: "miniWhisper")],
        expected: "miniWhisper works",
      ),
      Case(
        name: "vocabulary repairs casing",
        transcript: "Use miniwhisper and tca",
        vocabulary: ["MiniWhisper", "TCA"],
        corrections: [],
        expected: "Use MiniWhisper and TCA",
      ),
      Case(
        name: "vocabulary observes boundaries",
        transcript: "tca tcases",
        vocabulary: ["TCA"],
        corrections: [],
        expected: "TCA tcases",
      ),
      Case(
        name: "punctuation-ended terms match",
        transcript: "use c++17",
        vocabulary: ["C++"],
        corrections: [],
        expected: "use C++17",
      ),
      Case(
        name: "correction wins equal vocabulary match",
        transcript: "flow",
        vocabulary: ["FLOW"],
        corrections: [.init(misspelling: "flow", text: "Fluid")],
        expected: "Fluid",
      ),
      Case(
        name: "matching continues after overlap",
        transcript: "mini whisper and mini",
        vocabulary: [],
        corrections: [
          .init(misspelling: "mini whisper", text: "MiniWhisper"),
          .init(misspelling: "mini", text: "small"),
        ],
        expected: "MiniWhisper and small",
      ),
      Case(
        name: "quotes remain sentence-start punctuation",
        transcript: "He said. \"mini whisperer",
        vocabulary: [],
        corrections: [.init(misspelling: "mini whisperer", text: "miniwhisper")],
        expected: "He said. \"Miniwhisper",
      ),
      Case(
        name: "replacement capitalization skips leading punctuation",
        transcript: "mini whisperer works",
        vocabulary: [],
        corrections: [.init(misspelling: "mini whisperer", text: "'miniwhisper")],
        expected: "'Miniwhisper works",
      ),
    ],
  ) func `correction semantics`(testCase: Case) {
    let corrector = TranscriptCorrector(
      dictionary: TranscriptionDictionary(
        vocabulary: testCase.vocabulary, corrections: testCase.corrections,
      ),
    )

    #expect(corrector.apply(to: testCase.transcript) == testCase.expected)
  }
}
