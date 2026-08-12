@testable import Dictionary
import Foundation
import Testing

struct DictionaryCodingTests {
  @Test func `the exposed JSON shape round trips exactly`() throws {
    let addedAt = try #require(ISO8601DateFormatter().date(from: "2026-08-10T21:00:00Z"))
    let contents = DictionaryContents(
      vocabulary: [VocabularyEntry(text: "MiniWhisper", addedAt: addedAt)],
      corrections: [
        CorrectionEntry(misspelling: "mini whisperer", text: "MiniWhisper", addedAt: addedAt),
      ],
    )

    let data = try DictionaryCoding.encode(contents)

    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(object.keys) == ["vocabulary", "corrections"])
    let vocabulary = try #require(object["vocabulary"] as? [[String: Any]])
    #expect(try Set(#require(vocabulary.first).keys) == ["text", "addedAt"])
    #expect(try #require(vocabulary.first?["addedAt"] as? String) == "2026-08-10T21:00:00Z")
    let corrections = try #require(object["corrections"] as? [[String: Any]])
    #expect(try Set(#require(corrections.first).keys) == ["misspelling", "text", "addedAt"])
    #expect(try DictionaryCoding.decode(data) == contents)
  }

  @Test(
    arguments: [
      "not json",
      #"{"vocabulary":[]}"#,
      #"[]"#,
      #"{"vocabulary":[{"text":"","addedAt":"2026-08-10T21:00:00Z"}],"corrections":[]}"#,
      #"{"vocabulary":[],"corrections":[{"misspelling":"","text":"MiniWhisper","addedAt":"2026-08-10T21:00:00Z"}]}"#,
      #"{"vocabulary":[],"corrections":[{"misspelling":"mini whisperer","text":"","addedAt":"2026-08-10T21:00:00Z"}]}"#,
    ],
  ) func `malformed files fail fast`(contents: String) {
    #expect(throws: (any Error).self) {
      try DictionaryCoding.decode(Data(contents.utf8))
    }
  }
}
