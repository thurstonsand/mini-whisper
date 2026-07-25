import AVFAudio
import Foundation
import OSLog

private let performanceLogger = Logger(
  subsystem: "com.thurstonsand.MiniWhisper", category: "performance")

final class PreparedAudioEngine: @unchecked Sendable {
  let engine: AVAudioEngine
  let inputNode: AVAudioInputNode
  let inputFormat: AVAudioFormat
  let converter: CanonicalAudioConverter
  let inputBuffers: AudioBufferPool
  let tapRouter: CaptureTapRouter

  private let validityLock = NSLock()
  private var isValid = true

  private init(
    engine: AVAudioEngine, inputNode: AVAudioInputNode, inputFormat: AVAudioFormat,
    converter: CanonicalAudioConverter, inputBuffers: AudioBufferPool, tapRouter: CaptureTapRouter
  ) {
    self.engine = engine
    self.inputNode = inputNode
    self.inputFormat = inputFormat
    self.converter = converter
    self.inputBuffers = inputBuffers
    self.tapRouter = tapRouter
  }

  deinit { inputNode.removeTap(onBus: 0) }

  static func prepare() throws(AudioCaptureError) -> PreparedAudioEngine {
    let engine = AVAudioEngine()
    performanceLogger.notice("benchmark audio-engine-created")
    let inputNode = engine.inputNode
    let inputFormat = inputNode.outputFormat(forBus: 0)
    guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw .inputUnavailable }
    let inputBufferSize = try CaptureBufferConfiguration.frameCount(
      sampleRate: inputFormat.sampleRate)
    let converter = try CanonicalAudioConverter(inputFormat: inputFormat)
    let inputBuffers = try AudioBufferPool(format: inputFormat, bufferCapacity: inputBufferSize)
    let tapRouter = CaptureTapRouter()

    inputNode.installTap(onBus: 0, bufferSize: inputBufferSize, format: inputFormat) { buffer, _ in
      tapRouter.process(buffer)
    }
    engine.prepare()
    performanceLogger.notice("benchmark audio-engine-prewarmed")
    return PreparedAudioEngine(
      engine: engine, inputNode: inputNode, inputFormat: inputFormat, converter: converter,
      inputBuffers: inputBuffers, tapRouter: tapRouter)
  }

  var matchesCurrentInputFormat: Bool {
    validityLock.withLock { isValid } && inputNode.outputFormat(forBus: 0) == inputFormat
  }

  func invalidate() { validityLock.withLock { isValid = false } }
}

final class EngineCaptureSession: @unchecked Sendable {
  let events: AsyncStream<AudioCaptureEvent>

  private enum State: Equatable {
    case active
    case interrupted(AudioCaptureError)
    case closed
  }

  private let resources: PreparedAudioEngine
  private let processor: CaptureProcessor
  private let engineQueue = DispatchQueue(label: "MiniWhisper Audio Engine Lifecycle")
  private let stateLock = NSLock()

  private var state = State.active
  private var configurationObserver: (any NSObjectProtocol)?
  private var engineWatchdog: Task<Void, Never>?

  private init(
    resources: PreparedAudioEngine, processor: CaptureProcessor,
    events: AsyncStream<AudioCaptureEvent>
  ) {
    self.resources = resources
    self.processor = processor
    self.events = events
  }

  static func start(
    resources: PreparedAudioEngine
  ) throws(AudioCaptureError) -> EngineCaptureSession {
    let (events, continuation) = AsyncStream.makeStream(of: AudioCaptureEvent.self)
    let processor = CaptureProcessor(
      converter: resources.converter, continuation: continuation,
      inputBuffers: resources.inputBuffers)
    let session = EngineCaptureSession(resources: resources, processor: processor, events: events)
    resources.tapRouter.begin(processor: processor, continuation: continuation)

    do {
      try resources.engine.start()
      performanceLogger.notice("benchmark audio-engine-running")
    } catch {
      resources.tapRouter.end(processor: processor)
      processor.cancel()
      throw .engineStartFailed(error.localizedDescription)
    }

    session.configurationObserver = NotificationCenter.default.addObserver(
      forName: .AVAudioEngineConfigurationChange, object: resources.engine, queue: nil
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
        if !self.engineQueue.sync(execute: { self.resources.engine.isRunning }) {
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

    resources.invalidate()
    processor.fail(error)
    engineQueue.async { [self] in resources.engine.stop() }
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
    resources.tapRouter.end(processor: processor)
    engineQueue.sync { [resources] in resources.engine.stop() }
    return result.interruption
  }
}

final class CaptureTapRouter: @unchecked Sendable {
  private struct Destination {
    let processor: CaptureProcessor
    let firstBufferMarker: FirstBufferMarker
  }

  private let lock = NSLock()
  private var destination: Destination?

  func begin(processor: CaptureProcessor, continuation: AsyncStream<AudioCaptureEvent>.Continuation)
  {
    lock.withLock {
      precondition(destination == nil)
      destination = Destination(
        processor: processor, firstBufferMarker: FirstBufferMarker(continuation: continuation))
    }
  }

  func end(processor: CaptureProcessor) {
    lock.withLock { if destination?.processor === processor { destination = nil } }
  }

  func process(_ buffer: AVAudioPCMBuffer) {
    guard let destination = lock.withLock({ destination }) else { return }
    destination.firstBufferMarker.mark()
    destination.processor.process(buffer)
  }
}

private final class FirstBufferMarker: @unchecked Sendable {
  private let lock = NSLock()
  private let continuation: AsyncStream<AudioCaptureEvent>.Continuation
  private var hasMarked = false

  init(continuation: AsyncStream<AudioCaptureEvent>.Continuation) {
    self.continuation = continuation
  }

  func mark() {
    let shouldMark = lock.withLock {
      guard !hasMarked else { return false }
      hasMarked = true
      return true
    }
    guard shouldMark else { return }
    performanceLogger.notice("benchmark first-audio-buffer")
    continuation.yield(.captureBecameLive)
  }
}
