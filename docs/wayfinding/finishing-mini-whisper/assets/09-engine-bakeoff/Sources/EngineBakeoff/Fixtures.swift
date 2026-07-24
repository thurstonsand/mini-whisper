import Foundation

struct BakeoffError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

struct Fixture: Codable {
    let id: String
    let sourceFilename: String
    let filename: String
    let durationSeconds: Double
    let reference: String

    var fileURL: URL {
        prototypeRoot.appending(path: "fixtures").appending(path: filename)
    }

    func loadSamples() throws -> [Float] {
        let data = try Data(contentsOf: fileURL)
        guard data.count >= 44,
              String(bytes: data[0..<4], encoding: .ascii) == "RIFF",
              String(bytes: data[8..<12], encoding: .ascii) == "WAVE"
        else {
            throw BakeoffError("\(filename) is not a RIFF WAVE file")
        }

        var offset = 12
        var format: (code: Int, channels: Int, sampleRate: Int, bits: Int)?
        var sampleData: Range<Int>?
        while offset + 8 <= data.count {
            let id = String(bytes: data[offset..<(offset + 4)], encoding: .ascii) ?? ""
            let size = Int(littleEndianUInt32(data, at: offset + 4))
            let contentStart = offset + 8
            let contentEnd = min(contentStart + size, data.count)
            if id == "fmt ", contentEnd - contentStart >= 16 {
                format = (
                    Int(littleEndianUInt16(data, at: contentStart)),
                    Int(littleEndianUInt16(data, at: contentStart + 2)),
                    Int(littleEndianUInt32(data, at: contentStart + 4)),
                    Int(littleEndianUInt16(data, at: contentStart + 14))
                )
            } else if id == "data" {
                sampleData = contentStart..<contentEnd
            }
            offset = contentStart + size + (size & 1)
        }

        guard let format, format == (1, 1, 16_000, 16), let sampleData else {
            throw BakeoffError("\(filename) must be 16 kHz mono signed 16-bit PCM")
        }

        var samples: [Float] = []
        samples.reserveCapacity(sampleData.count / 2)
        var sampleOffset = sampleData.lowerBound
        while sampleOffset + 1 < sampleData.upperBound {
            let sample = Int16(bitPattern: littleEndianUInt16(data, at: sampleOffset))
            samples.append(Float(sample) / 32_768)
            sampleOffset += 2
        }
        return samples
    }
}

private struct FixtureManifest: Decodable {
    let fixtures: [Fixture]
}

func loadFixtures() throws -> [Fixture] {
    let url = prototypeRoot.appending(path: "fixtures/local-manifest.json")
    return try JSONDecoder().decode(FixtureManifest.self, from: Data(contentsOf: url)).fixtures
}

struct WordErrorStats {
    let errors: Int
    let referenceWords: Int

    var rate: Double {
        guard referenceWords > 0 else { return errors == 0 ? 0 : 1 }
        return Double(errors) / Double(referenceWords)
    }
}

func wordErrorStats(reference: String, hypothesis: String) -> WordErrorStats {
    let referenceWords = normalizedWords(reference)
    let hypothesisWords = normalizedWords(hypothesis)

    var previous = Array(0...hypothesisWords.count)
    for (referenceIndex, referenceWord) in referenceWords.enumerated() {
        var current = [referenceIndex + 1]
        for (hypothesisIndex, hypothesisWord) in hypothesisWords.enumerated() {
            current.append(
                min(
                    current[hypothesisIndex] + 1,
                    previous[hypothesisIndex + 1] + 1,
                    previous[hypothesisIndex] + (referenceWord == hypothesisWord ? 0 : 1)
                )
            )
        }
        previous = current
    }
    return WordErrorStats(errors: previous.last!, referenceWords: referenceWords.count)
}

private func normalizedWords(_ text: String) -> [String] {
    text.lowercased()
        .components(separatedBy: CharacterSet.alphanumerics.inverted)
        .filter { !$0.isEmpty }
}

private func littleEndianUInt16(_ data: Data, at offset: Int) -> UInt16 {
    UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
}

private func littleEndianUInt32(_ data: Data, at offset: Int) -> UInt32 {
    UInt32(data[offset]) | UInt32(data[offset + 1]) << 8
        | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
}
