import AVFAudio
import Foundation

final class EngineCaptureSession: @unchecked Sendable {
  let events: AsyncStream<AudioCaptureEvent>

  private enum State: Equatable {
    case active
    case interrupted(AudioCaptureError)
    case closed
  }

  private let engine: AVAudioEngine
  private let inputNode: AVAudioInputNode
  private let processor: CaptureProcessor
  private let engineQueue = DispatchQueue(label: "MiniWhisper Audio Engine Lifecycle")
  private let stateLock = NSLock()

  private var state = State.active
  private var configurationObserver: (any NSObjectProtocol)?
  private var engineWatchdog: Task<Void, Never>?

  private init(
    engine: AVAudioEngine, inputNode: AVAudioInputNode, processor: CaptureProcessor,
    events: AsyncStream<AudioCaptureEvent>
  ) {
    self.engine = engine
    self.inputNode = inputNode
    self.processor = processor
    self.events = events
  }

  static func start() throws(AudioCaptureError) -> EngineCaptureSession {
    let engine = AVAudioEngine()
    let inputNode = engine.inputNode
    let inputFormat = inputNode.outputFormat(forBus: 0)
    guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw .inputUnavailable }
    let inputBufferSize = try CaptureBufferConfiguration.frameCount(
      sampleRate: inputFormat.sampleRate)

    let (events, continuation) = AsyncStream.makeStream(
      of: AudioCaptureEvent.self, bufferingPolicy: .bufferingNewest(1))
    let processor = try CaptureProcessor(inputFormat: inputFormat, continuation: continuation)
    let session = EngineCaptureSession(
      engine: engine, inputNode: inputNode, processor: processor, events: events)

    inputNode.installTap(onBus: 0, bufferSize: inputBufferSize, format: inputFormat) { buffer, _ in
      processor.process(buffer)
    }
    engine.prepare()
    do { try engine.start() } catch {
      inputNode.removeTap(onBus: 0)
      processor.cancel()
      throw .engineStartFailed(error.localizedDescription)
    }

    session.configurationObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
    ) { [weak session] _ in session?.interrupt(with: .engineConfigurationChanged) }
    session.startEngineWatchdog()
    return session
  }

  func stop() throws(AudioCaptureError) -> CanonicalRecording {
    if let interruption = closeEngine() { processor.fail(interruption) }
    return try processor.complete()
  }

  func cancel() {
    _ = closeEngine()
    processor.cancel()
  }

  private func startEngineWatchdog() {
    engineWatchdog = Task { [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
        guard let self, self.isActive else { return }
        if !self.engineQueue.sync(execute: { self.engine.isRunning }) {
          self.interrupt(with: .engineStoppedUnexpectedly)
        }
      }
    }
  }

  private var isActive: Bool { stateLock.withLock { state == .active } }

  private func interrupt(with error: AudioCaptureError) {
    let shouldInterrupt = stateLock.withLock {
      guard state == .active else { return false }
      state = .interrupted(error)
      return true
    }
    guard shouldInterrupt else { return }

    processor.fail(error)
    engineQueue.async { [self] in engine.stop() }
  }

  private func closeEngine() -> AudioCaptureError? {
    let result = stateLock.withLock { () -> (shouldClose: Bool, interruption: AudioCaptureError?) in
      switch state {
      case .active:
        state = .closed
        return (true, nil)
      case .interrupted(let error):
        state = .closed
        return (true, error)
      case .closed: return (false, nil)
      }
    }
    guard result.shouldClose else { return result.interruption }

    engineWatchdog?.cancel()
    engineWatchdog = nil
    if let configurationObserver {
      NotificationCenter.default.removeObserver(configurationObserver)
      self.configurationObserver = nil
    }
    engineQueue.sync { [engine, inputNode] in
      engine.stop()
      inputNode.removeTap(onBus: 0)
    }
    return result.interruption
  }
}
