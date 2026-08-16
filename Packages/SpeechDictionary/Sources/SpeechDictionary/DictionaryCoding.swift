import Foundation

/// The on-disk shape of `dictionary.json`. The file is meant to be opened and edited by hand, so
/// it stays pretty-printed, key-sorted, and newline-terminated.
public enum DictionaryCoding {
  // MARK: Public

  public static func decode(_ data: Data) throws -> DictionaryContents {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let contents = try decoder.decode(DictionaryContents.self, from: data)
    return DictionaryContents(
      vocabulary: keepingLast(contents.vocabulary, keyedBy: \.text),
      corrections: keepingLast(contents.corrections, keyedBy: \.misspelling),
    )
  }

  public static func encode(_ contents: DictionaryContents) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var data = try encoder.encode(contents)
    data.append(0x0A)
    return data
  }

  // MARK: Private

  private static func keepingLast<Entry>(
    _ entries: [Entry], keyedBy keyPath: KeyPath<Entry, String>,
  ) -> [Entry] {
    var keys: Set<String> = []
    return entries.reversed()
      .filter {
        keys.insert($0[keyPath: keyPath].lowercased()).inserted
      }
      .reversed()
  }
}
