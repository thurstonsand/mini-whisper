import CoreAudio
import Foundation

/// Watches the device list and the system default for as long as someone is listening. The
/// CoreAudio callback does no blocking work; enumeration happens off it, and a Bluetooth burst of
/// notifications collapses into one snapshot.
public final class AudioInputDeviceMonitor: @unchecked Sendable {
  // MARK: Lifecycle

  private init(continuation: AsyncStream<AudioInputDeviceSnapshot>.Continuation) {
    self.continuation = continuation
    listener = { [weak self] _, _ in self?.scheduleRefresh() }
  }

  // MARK: Public

  public static func snapshots() -> AsyncStream<AudioInputDeviceSnapshot> {
    AsyncStream { continuation in
      let monitor = AudioInputDeviceMonitor(continuation: continuation)
      continuation.onTermination = { _ in monitor.stop() }
      monitor.start()
    }
  }

  // MARK: Private

  private static let observedAddresses = [
    AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain,
    ),
    AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain,
    ),
  ]

  private static let debounce = DispatchTimeInterval.milliseconds(250)

  private let continuation: AsyncStream<AudioInputDeviceSnapshot>.Continuation
  private let listenerQueue = DispatchQueue(label: "MiniWhisper CoreAudio Device Listener")
  private let refreshQueue = DispatchQueue(
    label: "MiniWhisper CoreAudio Device Enumeration", qos: .utility,
  )
  private var listener: AudioObjectPropertyListenerBlock!
  private var refreshWorkItem: DispatchWorkItem?
  private var isStarted = false

  private func start() {
    listenerQueue.async { [self] in
      guard !isStarted else {
        return
      }
      isStarted = true
      for var address in Self.observedAddresses {
        let status = AudioObjectAddPropertyListenerBlock(
          AudioObjectID(kAudioObjectSystemObject), &address, listenerQueue, listener,
        )
        precondition(status == noErr, "CoreAudio device listener failed: \(status)")
      }
      scheduleRefresh(delay: .nanoseconds(0))
    }
  }

  private func stop() {
    listenerQueue.async { [self] in
      guard isStarted else {
        return
      }
      isStarted = false
      refreshWorkItem?.cancel()
      refreshWorkItem = nil
      for var address in Self.observedAddresses {
        AudioObjectRemovePropertyListenerBlock(
          AudioObjectID(kAudioObjectSystemObject), &address, listenerQueue, listener,
        )
      }
    }
  }

  private func scheduleRefresh(delay: DispatchTimeInterval = debounce) {
    dispatchPrecondition(condition: .onQueue(listenerQueue))
    refreshWorkItem?.cancel()
    let workItem = DispatchWorkItem { [weak self] in self?.refresh() }
    refreshWorkItem = workItem
    listenerQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
  }

  private func refresh() {
    dispatchPrecondition(condition: .onQueue(listenerQueue))
    refreshQueue.async { [weak self] in
      guard let self, let snapshot = try? CoreAudioInputDevices.snapshot() else {
        return
      }
      continuation.yield(snapshot)
    }
  }
}
