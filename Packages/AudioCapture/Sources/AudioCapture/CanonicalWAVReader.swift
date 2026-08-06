import AVFAudio
import Foundation

public enum CanonicalWAVReader {
  /// Reads a WAV this package wrote. Anything that is not canonical is rejected rather than
  /// converted: the vault only ever stores canonical audio, so a mismatch means the file is not
  /// ours and resampling it would hide that.
  public static func read(contentsOf url: URL) throws(AudioCaptureError) -> CanonicalRecording {
    do {
      let file = try AVAudioFile(forReading: url)
      guard CanonicalAudioFormat.containsCanonicalSamples(file.processingFormat) else {
        throw AudioCaptureError.wavReadFailed("The recording is not in the canonical audio format")
      }
      guard
        let buffer = AVAudioPCMBuffer(
          pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length),
        )
      else {
        throw AudioCaptureError.wavReadFailed("The canonical audio buffer could not be allocated")
      }
      try file.read(into: buffer)
      guard let channel = buffer.floatChannelData?.pointee else {
        throw AudioCaptureError.wavReadFailed("The recording contained no samples")
      }
      return CanonicalRecording(
        samples: Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))),
      )
    } catch let error as AudioCaptureError {
      throw error
    } catch { throw .wavReadFailed(error.localizedDescription) }
  }
}
