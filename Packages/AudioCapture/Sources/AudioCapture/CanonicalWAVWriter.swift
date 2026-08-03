import AVFAudio
import Foundation

public enum CanonicalWAVWriter {
  public static func write(_ recording: CanonicalRecording, to url: URL) throws(AudioCaptureError) {
    guard recording.samples.count <= AVAudioFrameCount.max else {
      throw .wavWriteFailed("The recording is too long to store in one audio buffer")
    }
    guard let format = CanonicalAudioFormat.make() else {
      throw .wavWriteFailed("The canonical audio format could not be created")
    }
    guard
      let buffer = AVAudioPCMBuffer(
        pcmFormat: format, frameCapacity: AVAudioFrameCount(max(recording.samples.count, 1)),
      ),
      let channel = buffer.floatChannelData?.pointee
    else {
      throw .wavWriteFailed("The canonical audio buffer could not be allocated")
    }

    buffer.frameLength = AVAudioFrameCount(recording.samples.count)
    recording.samples.withUnsafeBufferPointer { samples in
      guard let baseAddress = samples.baseAddress else {
        return
      }
      channel.update(from: baseAddress, count: samples.count)
    }

    do {
      let file = try AVAudioFile(
        forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32,
        interleaved: false,
      )
      try file.write(from: buffer)
    } catch { throw .wavWriteFailed(error.localizedDescription) }
  }
}
