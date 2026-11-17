// Spike: posts MiniWhisper's default activation key, right Option, as HID events.
// Usage: hotkey down | up | key <keycode> | devices
import CoreAudio
import CoreGraphics
import Foundation

let rightOption: CGKeyCode = 61
let nonCoalesced: UInt64 = 0x100

func flags(_ down: Bool) {
  let event = CGEvent(keyboardEventSource: nil, virtualKey: rightOption, keyDown: down)!
  event.type = .flagsChanged
  event.flags = CGEventFlags(rawValue: down ? CGEventFlags.maskAlternate.rawValue | 0x40 | nonCoalesced : nonCoalesced)
  event.post(tap: .cghidEventTap)
}

func key(_ code: CGKeyCode) {
  CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)!.post(tap: .cghidEventTap)
  usleep(30_000)
  CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)!.post(tap: .cghidEventTap)
}

func devices() {
  var address = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)
  var size: UInt32 = 0
  AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
  var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
  AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids)
  for id in ids {
    var uidAddress = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var uid: Unmanaged<CFString>?
    var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    AudioObjectGetPropertyData(id, &uidAddress, 0, nil, &uidSize, &uid)
    print(uid?.takeRetainedValue() ?? "?" as CFString)
  }
}

switch CommandLine.arguments.dropFirst().first {
case "down": flags(true)
case "up": flags(false)
case "key": key(CGKeyCode(CommandLine.arguments[2])!)
case "devices": devices()
default: print("usage: hotkey down|up|key N|devices")
}
