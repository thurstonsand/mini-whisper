import AVFAudio
import Foundation

final class CanonicalAudioConverter: @unchecked Sendable {
  private static let outputBufferCapacity: AVAudioFrameCount = 4_096

  private let converter: AVAudioConverter
  private let outputFormat: AVAudioFormat
  private var reachedEndOfStream = false

  init(inputFormat: AVAudioFormat) throws(AudioCaptureError) {
    guard let outputFormat = CanonicalAudioFormat.make() else {
      throw .conversionFailed("The canonical audio format could not be created")
    }
    guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
      throw .unsupportedInputFormat(inputFormat.description)
    }
    converter.downmix = true

    self.converter = converter
    self.outputFormat = outputFormat
  }

  func reset() {
    converter.reset()
    reachedEndOfStream = false
  }

  func convert(_ inputBuffer: AVAudioPCMBuffer) throws(AudioCaptureError) -> [Float] {
    guard !reachedEndOfStream else {
      throw .conversionFailed("The audio converter has already finished")
    }

    let input = ConverterInput(buffer: inputBuffer)
    return try drain { _, status in input.provide(status: status) }
  }

  func finish() throws(AudioCaptureError) -> [Float] {
    guard !reachedEndOfStream else { return [] }
    reachedEndOfStream = true

    let input = ConverterInput(buffer: nil)
    return try drain { _, status in input.provide(status: status) }
  }

  private func drain(
    input: @escaping AVAudioConverterInputBlock
  ) throws(AudioCaptureError) -> [Float] {
    var outputSamples: [Float] = []
    var shouldContinue = true

    while shouldContinue {
      guard
        let outputBuffer = AVAudioPCMBuffer(
          pcmFormat: outputFormat, frameCapacity: Self.outputBufferCapacity)
      else { throw .conversionFailed("The canonical output buffer could not be allocated") }

      var conversionError: NSError?
      let status = converter.convert(
        to: outputBuffer, error: &conversionError, withInputFrom: input)
      if let conversionError { throw .conversionFailed(conversionError.localizedDescription) }

      outputSamples.append(contentsOf: try samples(from: outputBuffer))
      switch status {
      case .haveData: shouldContinue = true
      case .inputRanDry, .endOfStream: shouldContinue = false
      case .error: throw .conversionFailed("AVAudioConverter returned an error without details")
      @unknown default: throw .conversionFailed("AVAudioConverter returned an unknown status")
      }
    }

    return outputSamples
  }

  private func samples(from buffer: AVAudioPCMBuffer) throws(AudioCaptureError) -> [Float] {
    guard buffer.frameLength > 0 else { return [] }
    guard let channel = buffer.floatChannelData?.pointee else {
      throw .conversionFailed("Canonical Float32 samples were unavailable")
    }
    return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
  }
}

// AVAudioConverter invokes its input block synchronously inside convert; this object cannot race.
private final class ConverterInput: @unchecked Sendable {
  private let buffer: AVAudioPCMBuffer?
  private var suppliedBuffer = false

  init(buffer: AVAudioPCMBuffer?) { self.buffer = buffer }

  func provide(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
    guard let buffer else {
      status.pointee = .endOfStream
      return nil
    }
    guard !suppliedBuffer else {
      status.pointee = .noDataNow
      return nil
    }

    suppliedBuffer = true
    status.pointee = .haveData
    return buffer
  }
}
