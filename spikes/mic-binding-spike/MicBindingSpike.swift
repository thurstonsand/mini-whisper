import AudioToolbox
import AVFoundation
import CoreAudio
import Darwin
import Foundation

struct AudioDevice {
  let id: AudioDeviceID
  let uid: String
  let name: String
  let inputChannels: UInt32
}

enum SpikeError: Error, CustomStringConvertible {
  case coreAudio(String, OSStatus)
  case invalidProperty(String)
  case noMatch(String)
  case ambiguousMatch(String, [String])
  case bindingMismatch(expected: AudioDeviceID, actual: AudioDeviceID)
  case invalidFormat(String)
  case observedFormatMismatch(expected: String, actual: String)
  case noNonemptyBuffers

  var description: String {
    switch self {
    case let .coreAudio(operation, status):
      "\(operation) failed with OSStatus \(status)"
    case let .invalidProperty(property):
      "CoreAudio returned an invalid \(property) value"
    case let .noMatch(query):
      "No input device matched \"\(query)\""
    case let .ambiguousMatch(query, names):
      "Multiple input devices matched \"\(query)\": \(names.joined(separator: ", "))"
    case let .bindingMismatch(expected, actual):
      "CurrentDevice readback mismatch: expected \(expected), got \(actual)"
    case let .invalidFormat(format):
      "Input node returned an invalid format: \(format)"
    case let .observedFormatMismatch(expected, actual):
      "Tap buffer format mismatch: expected \(expected), got \(actual)"
    case .noNonemptyBuffers:
      "Capture produced zero nonempty buffers"
    }
  }
}

func propertyDataSize(
  objectID: AudioObjectID,
  address: inout AudioObjectPropertyAddress,
  operation: String
) throws -> UInt32 {
  var size: UInt32 = 0
  let status = AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size)
  guard status == noErr else { throw SpikeError.coreAudio(operation, status) }
  return size
}

func audioDeviceIDProperty(
  objectID: AudioObjectID,
  address: inout AudioObjectPropertyAddress,
  operation: String
) throws -> AudioDeviceID {
  var size = UInt32(MemoryLayout<AudioDeviceID>.size)
  var value = AudioDeviceID(kAudioObjectUnknown)
  let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
  guard status == noErr else { throw SpikeError.coreAudio(operation, status) }
  return value
}

func stringProperty(
  objectID: AudioObjectID,
  selector: AudioObjectPropertySelector,
  operation: String
) throws -> String {
  var address = AudioObjectPropertyAddress(
    mSelector: selector,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
  )
  var size = UInt32(MemoryLayout<CFString>.size)
  var value: CFString = "" as CFString
  let status = withUnsafeMutablePointer(to: &value) { pointer in
    AudioObjectGetPropertyData(
      objectID, &address, 0, nil, &size, UnsafeMutableRawPointer(pointer)
    )
  }
  guard status == noErr else { throw SpikeError.coreAudio(operation, status) }
  return value as String
}

func inputChannelCount(deviceID: AudioDeviceID) throws -> UInt32 {
  var address = AudioObjectPropertyAddress(
    mSelector: kAudioDevicePropertyStreamConfiguration,
    mScope: kAudioObjectPropertyScopeInput,
    mElement: kAudioObjectPropertyElementMain
  )
  var size = try propertyDataSize(
    objectID: deviceID, address: &address, operation: "read stream configuration size"
  )
  let storage = UnsafeMutableRawPointer.allocate(
    byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment
  )
  defer { storage.deallocate() }
  let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, storage)
  guard status == noErr else { throw SpikeError.coreAudio("read stream configuration", status) }
  let buffers = UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self))
  return buffers.reduce(0) { $0 + $1.mNumberChannels }
}

func inputDevices() throws -> [AudioDevice] {
  var address = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDevices,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
  )
  var size = try propertyDataSize(
    objectID: AudioObjectID(kAudioObjectSystemObject),
    address: &address,
    operation: "read device-list size"
  )
  let count = Int(size) / MemoryLayout<AudioDeviceID>.size
  var ids = [AudioDeviceID](repeating: 0, count: count)
  let status = ids.withUnsafeMutableBytes {
    AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, $0.baseAddress!
    )
  }
  guard status == noErr else { throw SpikeError.coreAudio("read device list", status) }

  return try ids.compactMap { id in
    let channels = try inputChannelCount(deviceID: id)
    guard channels > 0 else { return nil }
    return try AudioDevice(
      id: id,
      uid: stringProperty(
        objectID: id,
        selector: kAudioDevicePropertyDeviceUID,
        operation: "read device UID"
      ),
      name: stringProperty(
        objectID: id,
        selector: kAudioObjectPropertyName,
        operation: "read device name"
      ),
      inputChannels: channels
    )
  }
}

func defaultInputDeviceID() throws -> AudioDeviceID {
  var address = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultInputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
  )
  return try audioDeviceIDProperty(
    objectID: AudioObjectID(kAudioObjectSystemObject),
    address: &address,
    operation: "read default input device"
  )
}

final class CaptureStatistics: @unchecked Sendable {
  private let lock = NSLock()
  private var bufferCount = 0
  private var nonemptyBufferCount = 0
  private var peak: Float = 0
  private var observedFormat: AVAudioFormat?

  func consume(_ buffer: AVAudioPCMBuffer) {
    lock.withLock {
      bufferCount += 1
      if buffer.frameLength > 0 { nonemptyBufferCount += 1 }
      if observedFormat == nil { observedFormat = buffer.format }

      let audioBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
      for audioBuffer in audioBuffers {
        guard let data = audioBuffer.mData else { continue }
        let samples = data.assumingMemoryBound(to: Float.self)
        let sampleCount = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size
        for index in 0..<sampleCount { peak = max(peak, abs(samples[index])) }
      }
    }
  }

  func snapshot() -> (buffers: Int, nonempty: Int, peak: Float, observedFormat: AVAudioFormat?) {
    lock.withLock { (bufferCount, nonemptyBufferCount, peak, observedFormat) }
  }
}

func formatDescription(_ format: AVAudioFormat) -> String {
  "\(format.sampleRate) Hz / \(format.channelCount) ch"
}

enum EngineOrdering: String {
  case normal = "formats → tap(output) → prepare"
  case prepareBeforeFormats = "prepare → formats → tap(output)"
  case inputFormatTap = "formats → tap(input) → prepare"
}

func runCapture(
  label: String,
  boundDevice: AudioDevice?,
  ordering: EngineOrdering = .normal
) throws {
  let engine = AVAudioEngine()
  let inputNode = engine.inputNode
  var readbackID: AudioDeviceID

  if let boundDevice {
    guard let audioUnit = inputNode.audioUnit else {
      throw SpikeError.invalidProperty("input-node audio unit")
    }
    var requestedID = boundDevice.id
    let setStatus = AudioUnitSetProperty(
      audioUnit,
      kAudioOutputUnitProperty_CurrentDevice,
      kAudioUnitScope_Global,
      0,
      &requestedID,
      UInt32(MemoryLayout<AudioDeviceID>.size)
    )
    guard setStatus == noErr else { throw SpikeError.coreAudio("set CurrentDevice", setStatus) }

    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    readbackID = kAudioObjectUnknown
    let getStatus = AudioUnitGetProperty(
      audioUnit,
      kAudioOutputUnitProperty_CurrentDevice,
      kAudioUnitScope_Global,
      0,
      &readbackID,
      &size
    )
    guard getStatus == noErr else { throw SpikeError.coreAudio("read CurrentDevice", getStatus) }
    guard readbackID == boundDevice.id else {
      throw SpikeError.bindingMismatch(expected: boundDevice.id, actual: readbackID)
    }
  } else {
    readbackID = try defaultInputDeviceID()
  }

  if ordering == .prepareBeforeFormats {
    engine.prepare()
  }

  let nodeInputFormat = inputNode.inputFormat(forBus: 0)
  let nodeOutputFormat = inputNode.outputFormat(forBus: 0)
  guard nodeInputFormat.sampleRate > 0, nodeInputFormat.channelCount > 0 else {
    throw SpikeError.invalidFormat("input \(formatDescription(nodeInputFormat))")
  }
  guard nodeOutputFormat.sampleRate > 0, nodeOutputFormat.channelCount > 0 else {
    throw SpikeError.invalidFormat("output \(formatDescription(nodeOutputFormat))")
  }

  let tapFormat = ordering == .inputFormatTap ? nodeInputFormat : nodeOutputFormat
  let statistics = CaptureStatistics()
  inputNode.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { buffer, _ in
    statistics.consume(buffer)
  }
  defer {
    engine.stop()
    inputNode.removeTap(onBus: 0)
  }
  if ordering != .prepareBeforeFormats {
    engine.prepare()
  }
  try engine.start()
  Thread.sleep(forTimeInterval: 2.0)

  let result = statistics.snapshot()
  let observed = result.observedFormat.map(formatDescription) ?? "none"
  let peak = String(format: "%.6f", result.peak)
  print("RESULT | \(label) | ordering=\(ordering.rawValue) | readback=\(readbackID) | input=\(formatDescription(nodeInputFormat)) | output=\(formatDescription(nodeOutputFormat)) | tap=\(observed) | buffers=\(result.buffers) | nonempty=\(result.nonempty) | peak=\(peak)")

  if let observedFormat = result.observedFormat,
     observedFormat.sampleRate != tapFormat.sampleRate ||
     observedFormat.channelCount != tapFormat.channelCount {
    throw SpikeError.observedFormatMismatch(
      expected: formatDescription(tapFormat), actual: formatDescription(observedFormat)
    )
  }
  guard result.nonempty > 0 else { throw SpikeError.noNonemptyBuffers }
}

func setDefaultInputDevice(_ deviceID: AudioDeviceID) throws {
  var address = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultInputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
  )
  var mutableID = deviceID
  let status = AudioObjectSetPropertyData(
    AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
    UInt32(MemoryLayout<AudioDeviceID>.size), &mutableID
  )
  guard status == noErr else { throw SpikeError.coreAudio("set default input device", status) }
}

final class DefaultInputRestorer: @unchecked Sendable {
  init(savedID: AudioDeviceID) { self.savedID = savedID }

  func restore() {
    lock.withLock {
      guard !didRestore else { return }
      didRestore = true
      do {
        try setDefaultInputDevice(savedID)
        print("RESTORE | default input readback=\((try? defaultInputDeviceID()) ?? kAudioObjectUnknown)")
      } catch {
        fputs("RESTORE FAILED: \(error)\n", stderr)
      }
    }
  }

  private let savedID: AudioDeviceID
  private let lock = NSLock()
  private var didRestore = false
}

func runTemporaryDefaultArm(device: AudioDevice) throws {
  let savedID = try defaultInputDeviceID()
  let restorer = DefaultInputRestorer(savedID: savedID)
  let signalQueue = DispatchQueue(label: "Mic Binding Spike Default Restoration")
  Darwin.signal(SIGINT, SIG_IGN)
  Darwin.signal(SIGTERM, SIG_IGN)
  let interruptSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: signalQueue)
  let terminateSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: signalQueue)
  interruptSource.setEventHandler {
    restorer.restore()
    exit(128 + SIGINT)
  }
  terminateSource.setEventHandler {
    restorer.restore()
    exit(128 + SIGTERM)
  }
  interruptSource.resume()
  terminateSource.resume()
  defer {
    interruptSource.cancel()
    terminateSource.cancel()
    restorer.restore()
  }

  try setDefaultInputDevice(device.id)
  let changedReadback = try defaultInputDeviceID()
  guard changedReadback == device.id else {
    throw SpikeError.bindingMismatch(expected: device.id, actual: changedReadback)
  }
  print("TEMPORARY DEFAULT | saved=\(savedID) | selected=\(changedReadback) (\(device.name))")
  Thread.sleep(forTimeInterval: 0.5)
  try runCapture(label: "unbound temporary default \(device.name)", boundDevice: nil)
}

final class AUHALCapture: @unchecked Sendable {
  init(unit: AudioUnit, channels: UInt32) {
    self.unit = unit
    self.channels = channels
    storage = .allocate(capacity: maximumFrames * Int(channels))
  }

  deinit { storage.deallocate() }

  func render(
    flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>,
    timestamp: UnsafePointer<AudioTimeStamp>,
    frames: UInt32
  ) -> OSStatus {
    guard Int(frames) <= maximumFrames else { return kAudio_ParamError }
    let buffer = AudioBuffer(
      mNumberChannels: channels,
      mDataByteSize: frames * channels * UInt32(MemoryLayout<Float>.size),
      mData: storage
    )
    var list = AudioBufferList(mNumberBuffers: 1, mBuffers: buffer)
    let status = AudioUnitRender(unit, flags, timestamp, 1, frames, &list)
    lock.withLock {
      callbackCount += 1
      if status == noErr, frames > 0 {
        nonemptyFrameCount += Int(frames)
        for index in 0..<(Int(frames) * Int(channels)) {
          peak = max(peak, abs(storage[index]))
        }
      } else if status != noErr {
        renderErrorCount += 1
      }
    }
    return status
  }

  func snapshot() -> (callbacks: Int, frames: Int, peak: Float, errors: Int) {
    lock.withLock { (callbackCount, nonemptyFrameCount, peak, renderErrorCount) }
  }

  private let maximumFrames = 32_768
  private let unit: AudioUnit
  private let channels: UInt32
  private let storage: UnsafeMutablePointer<Float>
  private let lock = NSLock()
  private var callbackCount = 0
  private var nonemptyFrameCount = 0
  private var peak: Float = 0
  private var renderErrorCount = 0
}

let auhalInputCallback: AURenderCallback = { context, flags, timestamp, _, frames, _ in
  Unmanaged<AUHALCapture>.fromOpaque(context).takeUnretainedValue().render(
    flags: flags, timestamp: timestamp, frames: frames
  )
}

func runAUHALArm(device: AudioDevice) throws {
  var description = AudioComponentDescription(
    componentType: kAudioUnitType_Output,
    componentSubType: kAudioUnitSubType_HALOutput,
    componentManufacturer: kAudioUnitManufacturer_Apple,
    componentFlags: 0,
    componentFlagsMask: 0
  )
  guard let component = AudioComponentFindNext(nil, &description) else {
    throw SpikeError.invalidProperty("AUHAL component")
  }
  var optionalUnit: AudioUnit?
  let createStatus = AudioComponentInstanceNew(component, &optionalUnit)
  guard createStatus == noErr, let unit = optionalUnit else {
    throw SpikeError.coreAudio("create AUHAL", createStatus)
  }
  defer { AudioComponentInstanceDispose(unit) }

  var enableInput: UInt32 = 1
  var disableOutput: UInt32 = 0
  var status = AudioUnitSetProperty(
    unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1,
    &enableInput, UInt32(MemoryLayout<UInt32>.size)
  )
  guard status == noErr else { throw SpikeError.coreAudio("enable AUHAL input", status) }
  status = AudioUnitSetProperty(
    unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0,
    &disableOutput, UInt32(MemoryLayout<UInt32>.size)
  )
  guard status == noErr else { throw SpikeError.coreAudio("disable AUHAL output", status) }

  var selectedID = device.id
  status = AudioUnitSetProperty(
    unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
    &selectedID, UInt32(MemoryLayout<AudioDeviceID>.size)
  )
  guard status == noErr else { throw SpikeError.coreAudio("set AUHAL CurrentDevice", status) }
  var readbackID = AudioDeviceID(kAudioObjectUnknown)
  var readbackSize = UInt32(MemoryLayout<AudioDeviceID>.size)
  status = AudioUnitGetProperty(
    unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
    &readbackID, &readbackSize
  )
  guard status == noErr else { throw SpikeError.coreAudio("read AUHAL CurrentDevice", status) }
  guard readbackID == device.id else {
    throw SpikeError.bindingMismatch(expected: device.id, actual: readbackID)
  }

  var hardwareFormat = AudioStreamBasicDescription()
  var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
  status = AudioUnitGetProperty(
    unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1,
    &hardwareFormat, &formatSize
  )
  guard status == noErr else { throw SpikeError.coreAudio("read AUHAL hardware format", status) }
  let channels = hardwareFormat.mChannelsPerFrame
  guard hardwareFormat.mSampleRate > 0, channels > 0 else {
    throw SpikeError.invalidFormat("AUHAL hardware \(hardwareFormat.mSampleRate) Hz / \(channels) ch")
  }

  var clientFormat = AudioStreamBasicDescription(
    mSampleRate: hardwareFormat.mSampleRate,
    mFormatID: kAudioFormatLinearPCM,
    mFormatFlags: kAudioFormatFlagsNativeFloatPacked,
    mBytesPerPacket: UInt32(MemoryLayout<Float>.size) * channels,
    mFramesPerPacket: 1,
    mBytesPerFrame: UInt32(MemoryLayout<Float>.size) * channels,
    mChannelsPerFrame: channels,
    mBitsPerChannel: 32,
    mReserved: 0
  )
  status = AudioUnitSetProperty(
    unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1,
    &clientFormat, UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
  )
  guard status == noErr else { throw SpikeError.coreAudio("set AUHAL client format", status) }

  let capture = AUHALCapture(unit: unit, channels: channels)
  var callback = AURenderCallbackStruct(
    inputProc: auhalInputCallback,
    inputProcRefCon: Unmanaged.passUnretained(capture).toOpaque()
  )
  status = AudioUnitSetProperty(
    unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0,
    &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)
  )
  guard status == noErr else { throw SpikeError.coreAudio("set AUHAL input callback", status) }

  status = AudioUnitInitialize(unit)
  guard status == noErr else { throw SpikeError.coreAudio("initialize AUHAL", status) }
  defer { AudioUnitUninitialize(unit) }
  status = AudioOutputUnitStart(unit)
  guard status == noErr else { throw SpikeError.coreAudio("start AUHAL", status) }
  Thread.sleep(forTimeInterval: 2.0)
  AudioOutputUnitStop(unit)

  let result = capture.snapshot()
  print("AUHAL RESULT | explicit \(device.name) | readback=\(readbackID) | hardware=\(hardwareFormat.mSampleRate) Hz / \(channels) ch | callbacks=\(result.callbacks) | nonemptyFrames=\(result.frames) | renderErrors=\(result.errors) | peak=\(String(format: "%.6f", result.peak))")
}

func matchedDevice(query: String, devices: [AudioDevice]) throws -> AudioDevice {
  let matches = devices.filter { $0.uid.localizedCaseInsensitiveContains(query) }
  guard !matches.isEmpty else { throw SpikeError.noMatch(query) }
  guard matches.count == 1 else { throw SpikeError.ambiguousMatch(query, matches.map(\.name)) }
  return matches[0]
}

func main() throws {
  let devices = try inputDevices()
  print("INPUT DEVICES")
  for device in devices {
    print("DEVICE | id=\(device.id) | uid=\(device.uid) | name=\(device.name) | channels=\(device.inputChannels)")
  }

  guard CommandLine.arguments.count == 2 || CommandLine.arguments.count == 3 else {
    print("Usage: \(CommandLine.arguments[0]) [default-arm|auhal|engine-variants] <UID substring>")
    exit(64)
  }
  let mode = CommandLine.arguments.count == 3 ? CommandLine.arguments[1] : "engine"
  let query = CommandLine.arguments.last!
  let device = try matchedDevice(query: query, devices: devices)

  switch mode {
  case "default-arm":
    try runTemporaryDefaultArm(device: device)
  case "auhal":
    try runAUHALArm(device: device)
  case "engine-variants":
    var passingVariants = 0
    for ordering in [EngineOrdering.prepareBeforeFormats, .inputFormatTap] {
      do {
        try runCapture(
          label: "explicit \(device.name)", boundDevice: device, ordering: ordering
        )
        passingVariants += 1
      } catch {
        print("VARIANT FAIL | ordering=\(ordering.rawValue) | \(error)")
      }
    }
    guard passingVariants > 0 else { throw SpikeError.noNonemptyBuffers }
  case "engine":
    let defaultID = try defaultInputDeviceID()
    let defaultName = devices.first(where: { $0.id == defaultID })?.name ?? "unknown"
    try runCapture(label: "baseline system default (\(defaultName))", boundDevice: nil)
    try runCapture(label: "explicit \(device.name)", boundDevice: device)
  default:
    print("Unknown mode: \(mode)")
    exit(64)
  }
}

do {
  try main()
} catch {
  fputs("FAIL: \(error)\n", stderr)
  exit(1)
}
