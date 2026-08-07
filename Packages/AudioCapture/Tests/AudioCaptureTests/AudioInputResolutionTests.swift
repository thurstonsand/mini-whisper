@testable import AudioCapture
import Testing

struct AudioInputResolutionTests {
  // MARK: Internal

  @Test func `system default leaves the engine unbound`() {
    #expect(AudioInputRoute.resolving(.systemDefault, selectedDevice: nil) == .systemDefault)
  }

  @Test func `an available explicit device is bound`() {
    let route = AudioInputRoute.resolving(selection(for: studio), selectedDevice: studio)

    #expect(route == .explicit(studio))
  }

  @Test func `an absent explicit device falls back without changing the request`() {
    let selection = MicrophoneSelection.device(uid: "disconnected", lastKnownName: "Desk Mic")

    #expect(AudioInputRoute.resolving(selection, selectedDevice: nil) == .systemDefault)
    #expect(selection == .device(uid: "disconnected", lastKnownName: "Desk Mic"))
  }

  @Test func `A persisted Continuity selection falls back without changing the request`() {
    let continuity = AudioInputDevice(
      uid: "continuity", name: "iPhone Microphone", transport: .continuityCaptureWireless,
    )
    let selection = selection(for: continuity)

    #expect(AudioInputRoute.resolving(selection, selectedDevice: continuity) == .systemDefault)
    #expect(selection == .device(uid: "continuity", lastKnownName: "iPhone Microphone"))
  }

  @Test func `Continuity transports are excluded from explicit selection`() {
    let wired = AudioInputDevice(
      uid: "continuity-wired", name: "Wired iPhone", transport: .continuityCaptureWired,
    )
    let wireless = AudioInputDevice(
      uid: "continuity-wireless", name: "Wireless iPhone", transport: .continuityCaptureWireless,
    )

    #expect(
      AudioInputDevicePolicy.explicitlySelectableDevices([builtIn, wired, wireless]) == [builtIn],
    )
  }

  @Test func `declared hidden and private aggregate devices are excluded`() {
    let hidden = AudioInputDevice(uid: "hidden", name: "Hidden Device", visibility: .hidden)
    let privateAggregate = AudioInputDevice(
      uid: "private-aggregate", name: "Core Audio Bridge", transport: .aggregate,
      visibility: .privateAggregate,
    )
    let userAggregate = AudioInputDevice(
      uid: "user-aggregate", name: "Podcast Inputs", transport: .aggregate,
    )

    #expect(
      AudioInputDevicePolicy.explicitlySelectableDevices([
        builtIn, hidden, privateAggregate, userAggregate,
      ]) == [builtIn, userAggregate],
    )
  }

  /// The picker and the capture path must never disagree about what is selectable, which they
  /// cannot as long as both go through the one predicate.
  @Test func `every device the picker offers is one the route will bind`() {
    let continuity = AudioInputDevice(
      uid: "continuity", name: "iPhone Microphone", transport: .continuityCaptureWireless,
    )
    let offered = AudioInputDevicePolicy.explicitlySelectableDevices([
      builtIn, studio, continuity,
    ])

    for device in offered {
      #expect(
        AudioInputRoute.resolving(selection(for: device), selectedDevice: device)
          == .explicit(device),
      )
    }
  }

  // MARK: Private

  private let builtIn = AudioInputDevice(uid: "built-in", name: "Built-in Microphone")
  private let studio = AudioInputDevice(uid: "studio", name: "Studio Microphone")

  private func selection(for device: AudioInputDevice) -> MicrophoneSelection {
    .device(uid: device.uid, lastKnownName: device.name)
  }
}
