import AudioToolbox
import AVFAudio
import CoreAudio
import Foundation

/// An engine's input node, bound if the route asked for a specific device and left alone if it did
/// not. The format is read from the node afterwards rather than assumed, because binding is what
/// decides the rate and channel count.
struct AudioEngineInput {
  let engine: AVAudioEngine
  let node: AVAudioInputNode
  let format: AVAudioFormat

  static func make(
    binding: AudioInputBinding, engine: AVAudioEngine = AVAudioEngine(),
  ) throws(AudioCaptureError) -> AudioEngineInput {
    let node = engine.inputNode
    guard let audioUnit = node.audioUnit else {
      throw .inputUnavailable
    }

    if var deviceID = binding.explicitDeviceID {
      let status = AudioUnitSetProperty(
        audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
        &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size),
      )
      guard status == noErr else {
        throw .unexpected("bind input device failed with OSStatus \(status)")
      }
      var readbackID = AudioDeviceID(kAudioObjectUnknown)
      var readbackSize = UInt32(MemoryLayout<AudioDeviceID>.size)
      let readbackStatus = AudioUnitGetProperty(
        audioUnit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
        &readbackID, &readbackSize,
      )
      guard readbackStatus == noErr, readbackID == deviceID else {
        throw .unexpected(
          "input device binding readback was \(readbackID), expected \(deviceID)",
        )
      }
    }
    let format = node.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
      throw .inputUnavailable
    }
    return AudioEngineInput(engine: engine, node: node, format: format)
  }
}
