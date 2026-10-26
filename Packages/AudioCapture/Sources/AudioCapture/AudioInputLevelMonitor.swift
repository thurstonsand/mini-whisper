import AVFAudio
import Foundation

// MARK: - AudioInputLevelMonitor

/// A lightweight engine that exists only to paint the settings meter. It resolves and binds
/// through the same seam dictation uses, so the two can never disagree about which device is
/// being listened to, and CoreAudio's multi-client input lets them coexist. Failing to start is
/// silence, never an error: the meter simply stays inactive.
public enum AudioInputLevelMonitor {
  public static func levels(selection: MicrophoneSelection) -> AsyncStream<AudioLevel> {
    AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      let session = AudioInputLevelMonitorSession(
        selection: selection, continuation: continuation,
      )
      continuation.onTermination = { _ in session.stop() }
      session.start()
    }
  }
}

// MARK: - AudioInputLevelThrottle

struct AudioInputLevelThrottle {
  // MARK: Internal

  static let minimumIntervalNanoseconds: UInt64 = 33_333_333

  mutating func shouldPublish(now: UInt64) -> Bool {
    guard let lastPublishNanoseconds else {
      lastPublishNanoseconds = now
      return true
    }
    guard now - lastPublishNanoseconds >= Self.minimumIntervalNanoseconds else {
      return false
    }
    self.lastPublishNanoseconds = now
    return true
  }

  // MARK: Private

  private var lastPublishNanoseconds: UInt64?
}

// MARK: - AudioInputLevelMonitorSession

private final class AudioInputLevelMonitorSession: @unchecked Sendable {
  // MARK: Lifecycle

  init(selection: MicrophoneSelection, continuation: AsyncStream<AudioLevel>.Continuation) {
    self.selection = selection
    self.continuation = continuation
  }

  // MARK: Internal

  func start() {
    lifecycleQueue.async { [self] in
      guard stateLock.withLock({ isActive }), MicPermission.shared.status == .granted else {
        finish()
        return
      }
      do {
        let resolved = try CoreAudioInputDevices.resolve(selection)
        let input = try AudioEngineInput.make(binding: resolved.binding)
        input.node.installTap(onBus: 0, bufferSize: 1024, format: input.format) {
          [weak self] buffer, _ in self?.publish(buffer)
        }
        input.engine.prepare()
        try input.engine.start()
        guard stateLock.withLock({ isActive }) else {
          input.node.removeTap(onBus: 0)
          input.engine.stop()
          return
        }
        engine = input.engine
        inputNode = input.node
        configurationObserver = NotificationCenter.default.addObserver(
          forName: .AVAudioEngineConfigurationChange, object: input.engine, queue: nil,
        ) { [weak self] _ in self?.stop() }
      } catch {
        finish()
      }
    }
  }

  func stop() {
    let shouldStop = stateLock.withLock {
      guard isActive else {
        return false
      }
      isActive = false
      return true
    }
    guard shouldStop else {
      return
    }
    lifecycleQueue.async { [self] in
      if let configurationObserver {
        NotificationCenter.default.removeObserver(configurationObserver)
        self.configurationObserver = nil
      }
      inputNode?.removeTap(onBus: 0)
      engine?.stop()
      inputNode = nil
      engine = nil
      continuation.finish()
    }
  }

  // MARK: Private

  private let selection: MicrophoneSelection
  private let continuation: AsyncStream<AudioLevel>.Continuation
  private let lifecycleQueue = DispatchQueue(label: "MiniWhisper Input Level Monitor")
  private let stateLock = NSLock()
  private var engine: AVAudioEngine?
  private var inputNode: AVAudioInputNode?
  private var configurationObserver: (any NSObjectProtocol)?
  private var isActive = true
  private var throttle = AudioInputLevelThrottle()

  private func finish() {
    stateLock.withLock { isActive = false }
    continuation.finish()
  }

  private func publish(_ buffer: AVAudioPCMBuffer) {
    let now = DispatchTime.now().uptimeNanoseconds
    let shouldPublish = stateLock.withLock {
      isActive && throttle.shouldPublish(now: now)
    }
    guard shouldPublish, let level = level(from: buffer) else {
      return
    }
    continuation.yield(level)
  }

  private func level(from buffer: AVAudioPCMBuffer) -> AudioLevel? {
    guard buffer.frameLength > 0, let channels = buffer.floatChannelData else {
      return nil
    }
    let frameCount = Int(buffer.frameLength)
    let channelCount = Int(buffer.format.channelCount)
    var sumSquares: Float = 0
    if buffer.format.isInterleaved {
      for sample in UnsafeBufferPointer(
        start: channels[0], count: frameCount * channelCount,
      ) {
        sumSquares += sample * sample
      }
    } else {
      for channel in 0 ..< channelCount {
        for sample in UnsafeBufferPointer(start: channels[channel], count: frameCount) {
          sumSquares += sample * sample
        }
      }
    }
    return AudioLevel(sumSquares: sumSquares, sampleCount: frameCount * channelCount)
  }
}
