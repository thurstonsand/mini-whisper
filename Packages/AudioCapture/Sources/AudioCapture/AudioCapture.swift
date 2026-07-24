import Foundation

public enum AudioCaptureError: Error, Equatable, Sendable {
  case microphonePermission(MicPermissionStatus)
  case alreadyRecording
  case startCancelled
  case notRecording
  case captureSessionMismatch
  case inputUnavailable
  case unsupportedInputFormat(String)
  case conversionFailed(String)
  case captureOverrun
  case wavWriteFailed(String)
  case engineStartFailed(String)
  case engineConfigurationChanged
  case engineStoppedUnexpectedly
  case unexpected(String)
}

extension AudioCaptureError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .microphonePermission(.denied): "Microphone permission was denied"
    case .microphonePermission(.restricted): "Microphone access is restricted"
    case .microphonePermission(.undetermined): "Microphone permission remains undetermined"
    case .microphonePermission(.unknown): "Microphone permission has an unknown system status"
    case .microphonePermission(.granted):
      "Microphone permission was unexpectedly reported as granted"
    case .alreadyRecording: "Audio capture is already active"
    case .startCancelled: "Audio capture start was cancelled"
    case .notRecording: "Audio capture is not active"
    case .captureSessionMismatch: "The requested audio capture session is no longer active"
    case .inputUnavailable: "The default audio input is unavailable"
    case .unsupportedInputFormat(let format): "Unsupported input format: \(format)"
    case .conversionFailed(let reason): "Audio conversion failed: \(reason)"
    case .captureOverrun: "Audio capture could not keep up with the input stream"
    case .wavWriteFailed(let reason): "WAV writing failed: \(reason)"
    case .engineStartFailed(let reason): "The audio engine failed to start: \(reason)"
    case .engineConfigurationChanged: "The audio engine configuration changed during capture"
    case .engineStoppedUnexpectedly: "The audio engine stopped during capture"
    case .unexpected(let reason): "Unexpected audio capture failure: \(reason)"
    }
  }
}

public struct AudioLevel: Equatable, Sendable {
  public let decibels: Float
  public let normalizedPower: Float

  public init(decibels: Float, normalizedPower: Float) {
    self.decibels = decibels
    self.normalizedPower = normalizedPower
  }

  init(samples: [Float]) {
    guard !samples.isEmpty else {
      self.decibels = -60
      self.normalizedPower = 0
      return
    }

    let meanSquare = samples.reduce(Float.zero) { $0 + $1 * $1 } / Float(samples.count)
    let decibels = max(-60, 20 * log10(max(sqrt(meanSquare), Float.leastNonzeroMagnitude)))
    self.decibels = decibels
    self.normalizedPower = min(max((decibels + 60) / 60, 0), 1)
  }
}

public enum AudioCaptureEvent: Equatable, Sendable {
  case level(AudioLevel)
  case failed(AudioCaptureError)
}

public struct AudioCaptureSession: Sendable {
  public let id: UUID
  public let events: AsyncStream<AudioCaptureEvent>

  public init(id: UUID, events: AsyncStream<AudioCaptureEvent>) {
    self.id = id
    self.events = events
  }
}

public actor AudioCapture {
  public static let shared = AudioCapture()

  private var session: (id: UUID, capture: EngineCaptureSession)?
  private var isStarting = false

  public func start() async throws(AudioCaptureError) -> AudioCaptureSession {
    guard session == nil, !isStarting else { throw .alreadyRecording }
    isStarting = true
    defer { isStarting = false }

    let permission = await MicPermission.shared.requestIfNeeded()
    guard permission == .granted else { throw .microphonePermission(permission) }
    guard !Task.isCancelled else { throw .startCancelled }

    let capture = try EngineCaptureSession.start()
    let id = UUID()
    self.session = (id, capture)
    return AudioCaptureSession(id: id, events: capture.events)
  }

  public func stop(sessionID: UUID) throws(AudioCaptureError) -> CanonicalRecording {
    guard let session else { throw .notRecording }
    guard session.id == sessionID else { throw .captureSessionMismatch }
    self.session = nil
    return try session.capture.stop()
  }

  public func cancel(sessionID: UUID) {
    guard let session, session.id == sessionID else { return }
    self.session = nil
    session.capture.cancel()
  }
}
