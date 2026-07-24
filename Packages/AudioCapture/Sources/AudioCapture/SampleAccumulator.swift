struct SampleAccumulator: Equatable, Sendable {
  private(set) var samples: [Float] = []

  mutating func append(_ newSamples: [Float]) { samples.append(contentsOf: newSamples) }

  func recording() -> CanonicalRecording { CanonicalRecording(samples: samples) }
}
