import AVFAudio
import Foundation

// MARK: - CaptureProcessor

final class CaptureProcessor: @unchecked Sendable {
  // MARK: Lifecycle

  init(
    converter: CanonicalAudioConverter, continuation: AsyncStream<AudioCaptureEvent>.Continuation,
    inputBuffers: AudioBufferPool,
  ) {
    converter.reset()
    self.converter = converter
    self.continuation = continuation
    self.inputBuffers = inputBuffers
  }

  convenience init(
    inputFormat: AVAudioFormat, continuation: AsyncStream<AudioCaptureEvent>.Continuation,
  ) throws(AudioCaptureError) {
    try self.init(
      converter: CanonicalAudioConverter(inputFormat: inputFormat), continuation: continuation,
      inputBuffers: AudioBufferPool(
        format: inputFormat,
        bufferCapacity: CaptureBufferConfiguration.frameCount(sampleRate: inputFormat.sampleRate),
      ),
    )
  }

  // MARK: Internal

  func process(_ buffer: AVAudioPCMBuffer) {
    guard acceptingLock.withLock({ isAcceptingInput }) else {
      return
    }
    guard let inputBuffer = inputBuffers.copy(buffer) else {
      fail(.captureOverrun)
      return
    }

    worker.async { [self, inputBuffer] in
      defer { inputBuffers.checkIn(inputBuffer) }
      guard !isFinished, failure == nil else {
        return
      }

      do {
        let samples = try converter.convert(inputBuffer.buffer)
        accumulator.append(samples)
        if !samples.isEmpty {
          continuation.yield(.level(AudioLevel(samples: samples)))
        }
      } catch let error as AudioCaptureError { failFromWorker(error) } catch {
        failFromWorker(.conversionFailed(error.localizedDescription))
      }
    }
  }

  func fail(_ error: AudioCaptureError) {
    guard reserveFailure(error) else {
      return
    }
    worker.async { [self] in recordFailure(error) }
  }

  func complete() throws(AudioCaptureError) -> CanonicalRecording {
    let pendingFailure = acceptingLock.withLock {
      isAcceptingInput = false
      return self.pendingFailure
    }
    let result: Result<CanonicalRecording, AudioCaptureError> = worker.sync {
      guard !isFinished else {
        return .failure(.notRecording)
      }
      isFinished = true
      if let failure = failure ?? pendingFailure {
        return .failure(failure)
      }

      do {
        try accumulator.append(converter.finish())
        return .success(accumulator.recording())
      } catch let error as AudioCaptureError { return .failure(error) } catch {
        return .failure(.conversionFailed(error.localizedDescription))
      }
    }
    continuation.finish()
    return try result.get()
  }

  func cancel() {
    acceptingLock.withLock { isAcceptingInput = false }
    let shouldFinish = worker.sync {
      guard !isFinished else {
        return false
      }
      isFinished = true
      return true
    }
    if shouldFinish {
      continuation.finish()
    }
  }

  // MARK: Private

  private let acceptingLock = NSLock()
  private let converter: CanonicalAudioConverter
  private let continuation: AsyncStream<AudioCaptureEvent>.Continuation
  private let inputBuffers: AudioBufferPool
  private let worker = DispatchQueue(label: "MiniWhisper Audio Capture Processor")

  private var accumulator = SampleAccumulator()
  private var failure: AudioCaptureError?
  private var pendingFailure: AudioCaptureError?
  private var isAcceptingInput = true
  private var isFinished = false

  private func failFromWorker(_ error: AudioCaptureError) {
    guard reserveFailure(error) else {
      return
    }
    recordFailure(error)
  }

  private func reserveFailure(_ error: AudioCaptureError) -> Bool {
    acceptingLock.withLock {
      guard isAcceptingInput else {
        return false
      }
      isAcceptingInput = false
      pendingFailure = error
      return true
    }
  }

  private func recordFailure(_ error: AudioCaptureError) {
    guard !isFinished, failure == nil else {
      return
    }
    failure = error
    continuation.yield(.failed(error))
    continuation.finish()
  }
}

// MARK: - CaptureBufferConfiguration

enum CaptureBufferConfiguration {
  static let durationSeconds = 0.1

  static func frameCount(sampleRate: Double) throws(AudioCaptureError) -> AVAudioFrameCount {
    let frameCount = ceil(sampleRate * durationSeconds)
    guard frameCount > 0, frameCount <= Double(AVAudioFrameCount.max) else {
      throw .unsupportedInputFormat("Invalid sample rate: \(sampleRate)")
    }
    return AVAudioFrameCount(frameCount)
  }
}

// MARK: - AudioBufferPool

final class AudioBufferPool: @unchecked Sendable {
  // MARK: Lifecycle

  init(format: AVAudioFormat, bufferCapacity: AVAudioFrameCount) throws(AudioCaptureError) {
    var buffers: [OwnedAudioBuffer] = []
    for _ in 0 ..< Self.bufferCount {
      guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferCapacity) else {
        throw .unexpected("An input audio buffer could not be allocated")
      }
      buffers.append(OwnedAudioBuffer(buffer))
    }
    availableBuffers = buffers
  }

  // MARK: Internal

  func copy(_ source: AVAudioPCMBuffer) -> OwnedAudioBuffer? {
    guard let destination = lock.withLock({ availableBuffers.popLast() }) else {
      return nil
    }
    guard copy(source, to: destination.buffer) else {
      checkIn(destination)
      return nil
    }
    return destination
  }

  func checkIn(_ buffer: OwnedAudioBuffer) {
    buffer.buffer.frameLength = 0
    lock.withLock { availableBuffers.append(buffer) }
  }

  // MARK: Private

  private static let bufferCount = 8

  private let lock = NSLock()
  private var availableBuffers: [OwnedAudioBuffer]

  private func copy(_ source: AVAudioPCMBuffer, to destination: AVAudioPCMBuffer) -> Bool {
    guard source.frameLength <= destination.frameCapacity else {
      return false
    }

    destination.frameLength = destination.frameCapacity
    let sourceBuffers = UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
    let destinationBuffers = UnsafeMutableAudioBufferListPointer(destination.mutableAudioBufferList)
    guard sourceBuffers.count == destinationBuffers.count else {
      return false
    }

    for index in sourceBuffers.indices {
      let sourceBuffer = sourceBuffers[index]
      let byteCount = Int(sourceBuffer.mDataByteSize)
      guard byteCount <= Int(destinationBuffers[index].mDataByteSize) else {
        return false
      }
      guard byteCount > 0 else {
        continue
      }
      guard let sourceData = sourceBuffer.mData,
            let destinationData = destinationBuffers[index].mData
      else {
        return false
      }
      memcpy(destinationData, sourceData, byteCount)
    }
    destination.frameLength = source.frameLength
    return true
  }
}

// MARK: - OwnedAudioBuffer

final class OwnedAudioBuffer: @unchecked Sendable {
  // MARK: Lifecycle

  init(_ buffer: AVAudioPCMBuffer) {
    self.buffer = buffer
  }

  // MARK: Internal

  let buffer: AVAudioPCMBuffer
}
