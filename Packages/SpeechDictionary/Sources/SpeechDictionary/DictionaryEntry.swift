import Foundation

// MARK: - VocabularyEntry

public struct VocabularyEntry: Codable, Equatable, Sendable {
  // MARK: Lifecycle

  public init(text: String, addedAt: Date) {
    self.text = text
    self.addedAt = addedAt
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    text = try container.decode(String.self, forKey: .text)
    guard !text.isEmpty else {
      throw DecodingError.dataCorruptedError(
        forKey: .text, in: container, debugDescription: "Vocabulary text cannot be empty",
      )
    }
    addedAt = try container.decode(Date.self, forKey: .addedAt)
  }

  // MARK: Public

  public var text: String
  public let addedAt: Date
}

// MARK: - CorrectionEntry

public struct CorrectionEntry: Codable, Equatable, Sendable {
  // MARK: Lifecycle

  public init(misspelling: String, text: String, addedAt: Date) {
    self.misspelling = misspelling
    self.text = text
    self.addedAt = addedAt
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    misspelling = try container.decode(String.self, forKey: .misspelling)
    guard !misspelling.isEmpty else {
      throw DecodingError.dataCorruptedError(
        forKey: .misspelling, in: container,
        debugDescription: "Correction misspelling cannot be empty",
      )
    }
    text = try container.decode(String.self, forKey: .text)
    guard !text.isEmpty else {
      throw DecodingError.dataCorruptedError(
        forKey: .text, in: container, debugDescription: "Correction text cannot be empty",
      )
    }
    addedAt = try container.decode(Date.self, forKey: .addedAt)
  }

  // MARK: Public

  public var misspelling: String
  public var text: String
  public let addedAt: Date
}

// MARK: - DictionaryContents

public struct DictionaryContents: Codable, Equatable, Sendable {
  // MARK: Lifecycle

  public init(
    vocabulary: [VocabularyEntry] = [], corrections: [CorrectionEntry] = [],
  ) {
    self.vocabulary = vocabulary
    self.corrections = corrections
  }

  // MARK: Public

  public static let empty = DictionaryContents()

  public var vocabulary: [VocabularyEntry]
  public var corrections: [CorrectionEntry]
}
