// Capture microphone audio to a 16 kHz mono WAV until stdin delivers a line.
// The corpus recorder shells out to this instead of ffmpeg's avfoundation
// input, whose demuxer drops buffer fragments and leaves audible crackle.
// AVAudioEngine is the same capture path the app itself uses.
//
//   swiftc -O mic-record.swift -o .build/mic-record
//   .build/mic-record out.wav   # Enter (or closed stdin) stops it

import AVFoundation

guard CommandLine.arguments.count == 2 else {
  FileHandle.standardError.write(Data("usage: mic-record <out.wav>\n".utf8))
  exit(2)
}
let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])

let engine = AVAudioEngine()
let input = engine.inputNode
let inputFormat = input.outputFormat(forBus: 0)
let targetFormat = AVAudioFormat(
  commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true,
)!
guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
  FileHandle.standardError.write(Data("cannot convert \(inputFormat) to 16 kHz mono\n".utf8))
  exit(1)
}
// Optional so it can be released before exit: AVAudioFile finalizes the WAV
// header on deallocation, and a global that lives until exit() never does.
var file: AVAudioFile? = try AVAudioFile(
  forWriting: outputURL,
  settings: targetFormat.settings,
  commonFormat: .pcmFormatInt16,
  interleaved: true,
)

input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
  let capacity = AVAudioFrameCount(
    Double(buffer.frameLength) * targetFormat.sampleRate / inputFormat.sampleRate + 32)
  let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity)!
  var consumed = false
  var conversionError: NSError?
  converter.convert(to: converted, error: &conversionError) { _, status in
    if consumed {
      status.pointee = .noDataNow
      return nil
    }
    consumed = true
    status.pointee = .haveData
    return buffer
  }
  if conversionError == nil, converted.frameLength > 0 {
    try? file?.write(from: converted)
  }
}

try engine.start()
_ = readLine()
engine.stop()
input.removeTap(onBus: 0)
file = nil
