import Foundation
@testable import SpeechDictionary
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

  @Test func `duplicate keys keep their last occurrence`() throws {
    let contents = """
    {
      "vocabulary": [
        {"text":"TCA","addedAt":"2026-08-10T20:00:00Z"},
        {"text":"tca","addedAt":"2026-08-10T21:00:00Z"}
      ],
      "corrections": [
        {"misspelling":"mini whisper","text":"Miniwhisper","addedAt":"2026-08-10T20:00:00Z"},
        {"misspelling":"MINI WHISPER","text":"MiniWhisper","addedAt":"2026-08-10T21:00:00Z"}
      ]
    }
    """

    let dictionary = try DictionaryCoding.decode(Data(contents.utf8))

    #expect(dictionary.vocabulary.map(\.text) == ["tca"])
    #expect(dictionary.corrections.map(\.misspelling) == ["MINI WHISPER"])
    #expect(dictionary.corrections.map(\.text) == ["MiniWhisper"])
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
