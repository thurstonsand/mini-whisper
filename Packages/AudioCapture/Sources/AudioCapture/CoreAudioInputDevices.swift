import AudioToolbox
import CoreAudio
import Foundation

// MARK: - AudioInputBinding

/// What the engine is told about its input. `systemDefault` carries the device the route landed on
/// only so a prewarmed engine can notice the default moved underneath it; that engine is never
/// bound, which is what lets a Continuity default work and erases default-churn staleness.
enum AudioInputBinding: Equatable {
  case systemDefault(resolved: AudioDeviceID)
  case explicit(AudioDeviceID)

  // MARK: Internal

  /// Present only for an explicit route, so binding and not-binding cannot be confused.
  var explicitDeviceID: AudioDeviceID? {
    switch self {
    case .systemDefault:
      nil
    case let .explicit(id):
      id
    }
  }
}

// MARK: - ResolvedAudioInput

struct ResolvedAudioInput: Equatable {
  let binding: AudioInputBinding
  /// What actually records, which is not always what was asked for.
  let deviceName: String
}

// MARK: - CoreAudioInputDevices

enum CoreAudioInputDevices {
  // MARK: Internal

  static func snapshot() throws(AudioCaptureError) -> AudioInputDeviceSnapshot {
    var inputDevices: [AudioInputDevice] = []
    for id in try deviceIDs() where try inputChannelCount(id: id) > 0 {
      try inputDevices.append(device(id: id))
    }
    var devices = AudioInputDevicePolicy.explicitlySelectableDevices(inputDevices)
    devices.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    let defaultID = try defaultInputDeviceID()
    let defaultDevice = defaultID == kAudioObjectUnknown ? nil : try device(id: defaultID)
    return AudioInputDeviceSnapshot(devices: devices, defaultDevice: defaultDevice)
  }

  /// Resolved fresh immediately before every prepare and start: an `AudioDeviceID` is a handle,
  /// not an identity, so none is ever persisted or cached. An unknown ID means the device is
  /// absent, which is a fallback rather than an error.
  static func resolve(
    _ selection: MicrophoneSelection,
  ) throws(AudioCaptureError) -> ResolvedAudioInput {
    var selected: (id: AudioDeviceID, device: AudioInputDevice)?
    if case let .device(uid, _) = selection {
      let id = try translate(uid: uid)
      if id != kAudioObjectUnknown {
        selected = try (id, device(id: id))
      }
    }
    if case .explicit = AudioInputRoute.resolving(selection, selectedDevice: selected?.device),
       let selected
    {
      return ResolvedAudioInput(
        binding: .explicit(selected.id), deviceName: selected.device.name,
      )
    }
    let defaultID = try defaultInputDeviceID()
    guard defaultID != kAudioObjectUnknown else {
      throw .inputUnavailable
    }
    let defaultDevice = try device(id: defaultID)
    return ResolvedAudioInput(
      binding: .systemDefault(resolved: defaultID), deviceName: defaultDevice.name,
    )
  }

  // MARK: Private

  private static func deviceIDs() throws(AudioCaptureError) -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain,
    )
    var size: UInt32 = 0
    try check(
      AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size,
      ),
      operation: "read audio device list size",
    )
    var ids = [AudioDeviceID](
      repeating: kAudioObjectUnknown,
      count: Int(size) / MemoryLayout<AudioDeviceID>.size,
    )
    let status = ids.withUnsafeMutableBytes { bytes in
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size,
        bytes.baseAddress!,
      )
    }
    try check(status, operation: "read audio device list")
    return ids
  }

  private static func inputChannelCount(id: AudioDeviceID) throws(AudioCaptureError) -> UInt32 {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreamConfiguration,
      mScope: kAudioObjectPropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain,
    )
    var size: UInt32 = 0
    try check(
      AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size),
      operation: "read input stream configuration size",
    )
    let storage = UnsafeMutableRawPointer.allocate(
      byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment,
    )
    defer { storage.deallocate() }
    try check(
      AudioObjectGetPropertyData(id, &address, 0, nil, &size, storage),
      operation: "read input stream configuration",
    )
    return UnsafeMutableAudioBufferListPointer(
      storage.assumingMemoryBound(to: AudioBufferList.self),
    ).reduce(0) { $0 + $1.mNumberChannels }
  }

  private static func defaultInputDeviceID() throws(AudioCaptureError) -> AudioDeviceID {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain,
    )
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var value = AudioDeviceID(kAudioObjectUnknown)
    try check(
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &value,
      ),
      operation: "read default input device",
    )
    return value
  }

  private static func translate(uid: String) throws(AudioCaptureError) -> AudioDeviceID {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain,
    )
    var uid = uid as CFString
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var id = AudioDeviceID(kAudioObjectUnknown)
    let status = withUnsafePointer(to: &uid) { pointer in
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address,
        UInt32(MemoryLayout<CFString>.size), pointer, &size, &id,
      )
    }
    try check(status, operation: "translate input device UID")
    return id
  }

  private static func device(id: AudioDeviceID) throws(AudioCaptureError) -> AudioInputDevice {
    let transport = try inputTransport(id: id)
    return try AudioInputDevice(
      uid: stringProperty(
        objectID: id, selector: kAudioDevicePropertyDeviceUID,
        operation: "read input device UID",
      ),
      name: stringProperty(
        objectID: id, selector: kAudioObjectPropertyName,
        operation: "read input device name",
      ),
      transport: transport,
      visibility: inputVisibility(id: id, transport: transport),
    )
  }

  private static func inputVisibility(
    id: AudioDeviceID, transport: AudioInputTransport,
  ) throws(AudioCaptureError) -> AudioInputVisibility {
    var hiddenAddress = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyIsHidden,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain,
    )
    var hiddenSize = UInt32(MemoryLayout<UInt32>.size)
    var isHidden: UInt32 = 0
    try check(
      AudioObjectGetPropertyData(id, &hiddenAddress, 0, nil, &hiddenSize, &isHidden),
      operation: "read input device visibility",
    )
    if isHidden != 0 {
      return .hidden
    }

    guard transport == .aggregate else {
      return .visible
    }
    var compositionAddress = AudioObjectPropertyAddress(
      mSelector: kAudioAggregateDevicePropertyComposition,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain,
    )
    guard AudioObjectHasProperty(id, &compositionAddress) else {
      return .visible
    }
    var compositionSize = UInt32(MemoryLayout<CFDictionary>.size)
    var composition: CFDictionary = [:] as CFDictionary
    let status = withUnsafeMutablePointer(to: &composition) { pointer in
      AudioObjectGetPropertyData(
        id, &compositionAddress, 0, nil, &compositionSize, UnsafeMutableRawPointer(pointer),
      )
    }
    try check(status, operation: "read aggregate device composition")
    let isPrivate = (composition as NSDictionary)[kAudioAggregateDeviceIsPrivateKey] as? NSNumber
    return isPrivate?.boolValue == true ? .privateAggregate : .visible
  }

  private static func inputTransport(
    id: AudioDeviceID,
  ) throws(AudioCaptureError) -> AudioInputTransport {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyTransportType,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain,
    )
    var size = UInt32(MemoryLayout<UInt32>.size)
    var value: UInt32 = 0
    try check(
      AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value),
      operation: "read input device transport",
    )
    switch value {
    case kAudioDeviceTransportTypeAggregate:
      return .aggregate
    case kAudioDeviceTransportTypeContinuityCaptureWired:
      return .continuityCaptureWired
    case kAudioDeviceTransportTypeContinuityCaptureWireless:
      return .continuityCaptureWireless
    default:
      return .ordinary
    }
  }

  private static func stringProperty(
    objectID: AudioObjectID,
    selector: AudioObjectPropertySelector,
    operation: String,
  ) throws(AudioCaptureError) -> String {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain,
    )
    var size = UInt32(MemoryLayout<CFString>.size)
    var value: CFString = "" as CFString
    let status = withUnsafeMutablePointer(to: &value) { pointer in
      AudioObjectGetPropertyData(
        objectID, &address, 0, nil, &size, UnsafeMutableRawPointer(pointer),
      )
    }
    try check(status, operation: operation)
    return value as String
  }

  private static func check(_ status: OSStatus, operation: String) throws(AudioCaptureError) {
    guard status == noErr else {
      throw .unexpected("\(operation) failed with OSStatus \(status)")
    }
  }
}
