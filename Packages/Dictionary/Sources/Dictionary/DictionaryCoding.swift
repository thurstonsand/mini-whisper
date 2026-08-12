import Foundation

/// The on-disk shape of `dictionary.json`. The file is meant to be opened and edited by hand, so
/// it stays pretty-printed, key-sorted, and newline-terminated.
public enum DictionaryCoding {
  public static func decode(_ data: Data) throws -> DictionaryContents {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(DictionaryContents.self, from: data)
  }

  public static func encode(_ contents: DictionaryContents) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    var data = try encoder.encode(contents)
    data.append(0x0A)
    return data
  }
}
