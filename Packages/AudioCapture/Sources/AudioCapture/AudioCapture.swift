import AVFoundation
import Foundation
import OSLog

private let performanceLogger = Logger(
  subsystem: "com.thurstonsand.MiniWhisper", category: "performance",
)

// MARK: - AudioCaptureError

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
  case wavReadFailed(String)
  case engineStartFailed(String)
  case engineConfigurationChanged
  case engineStoppedUnexpectedly
  case unexpected(String)
}

// MARK: LocalizedError

extension AudioCaptureError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .microphonePermission(.denied):
      "Microphone permission was denied"
    case .microphonePermission(.restricted):
      "Microphone access is restricted"
    case .microphonePermission(.undetermined):
      "Microphone permission remains undetermined"
    case .microphonePermission(.unknown):
      "Microphone permission has an unknown system status"
    case .microphonePermission(.granted):
      "Microphone permission was unexpectedly reported as granted"
    case .alreadyRecording:
      "Audio capture is already active"
    case .startCancelled:
      "Audio capture start was cancelled"
    case .notRecording:
      "Audio capture is not active"
    case .captureSessionMismatch:
      "The requested audio capture session is no longer active"
    case .inputUnavailable:
      "The default audio input is unavailable"
    case let .unsupportedInputFormat(format):
      "Unsupported input format: \(format)"
    case let .conversionFailed(reason):
      "Audio conversion failed: \(reason)"
    case .captureOverrun:
      "Audio capture could not keep up with the input stream"
    case let .wavWriteFailed(reason):
      "WAV writing failed: \(reason)"
    case let .wavReadFailed(reason):
      "WAV reading failed: \(reason)"
    case let .engineStartFailed(reason):
      "The audio engine failed to start: \(reason)"
    case .engineConfigurationChanged:
      "The audio engine configuration changed during capture"
    case .engineStoppedUnexpectedly:
      "The audio engine stopped during capture"
    case let .unexpected(reason):
      "Unexpected audio capture failure: \(reason)"
    }
  }
}

// MARK: - AudioLevel

public struct AudioLevel: Equatable, Sendable {
  // MARK: Lifecycle

  public init(decibels: Float, normalizedPower: Float) {
    self.decibels = decibels
    self.normalizedPower = normalizedPower
  }

  init(samples: [Float]) {
    guard !samples.isEmpty else {
      self.decibels = -60
      normalizedPower = 0
      return
    }

    let meanSquare = samples.reduce(Float.zero) { $0 + $1 * $1 } / Float(samples.count)
    let decibels = max(-60, 20 * log10(max(sqrt(meanSquare), Float.leastNonzeroMagnitude)))
    self.decibels = decibels
    normalizedPower = min(max((decibels + 60) / 60, 0), 1)
  }

  // MARK: Public

  public let decibels: Float
  public let normalizedPower: Float
}

// MARK: - AudioCaptureEvent

public enum AudioCaptureEvent: Equatable, Sendable {
  case captureBecameLive
  case level(AudioLevel)
  case failed(AudioCaptureError)
}

// MARK: - AudioCaptureSession

public struct AudioCaptureSession: Sendable {
  // MARK: Lifecycle

  public init(id: UUID, inputDeviceName: String, events: AsyncStream<AudioCaptureEvent>) {
    self.id = id
    self.inputDeviceName = inputDeviceName
    self.events = events
  }

  // MARK: Public

  public let id: UUID
  public let inputDeviceName: String
  public let events: AsyncStream<AudioCaptureEvent>
}

// MARK: - AudioCapture

public actor AudioCapture {
  // MARK: Public

  public static let shared = AudioCapture()

  public static var defaultInputDeviceName: String? {
    AVCaptureDevice.default(for: .audio)?.localizedName
  }

  public func prepare() throws(AudioCaptureError) {
    guard MicPermission.shared.status == .granted else {
      return
    }
    _ = try preparedAudioEngine()
  }

  public func start() async throws(AudioCaptureError) -> AudioCaptureSession {
    performanceLogger.notice("benchmark audio-capture-start-entered")
    guard session == nil, !isStarting else {
      throw .alreadyRecording
    }
    isStarting = true
    defer { isStarting = false }

    let permission = await MicPermission.shared.requestIfNeeded()
    performanceLogger.notice("benchmark microphone-permission-resolved")
    guard permission == .granted else {
      throw .microphonePermission(permission)
    }
    guard !Task.isCancelled else {
      throw .startCancelled
    }

    guard let inputDeviceName = Self.defaultInputDeviceName else {
      throw .inputUnavailable
    }
    let capture = try EngineCaptureSession.start(resources: preparedAudioEngine())
    performanceLogger.notice("benchmark audio-engine-start-returned")
    let id = UUID()
    session = (id, capture)
    return AudioCaptureSession(id: id, inputDeviceName: inputDeviceName, events: capture.events)
  }

  public func stop(sessionID: UUID) throws(AudioCaptureError) -> CanonicalRecording {
    guard let session else {
      throw .notRecording
    }
    guard session.id == sessionID else {
      throw .captureSessionMismatch
    }
    self.session = nil
    return try session.capture.stop()
  }

  public func cancel(sessionID: UUID) {
    guard let session, session.id == sessionID else {
      return
    }
    self.session = nil
    session.capture.cancel()
  }

  // MARK: Private

  private var preparedEngine: PreparedAudioEngine?
  private var session: (id: UUID, capture: EngineCaptureSession)?
  private var isStarting = false

  private func preparedAudioEngine() throws(AudioCaptureError) -> PreparedAudioEngine {
    if let preparedEngine, preparedEngine.matchesCurrentInputFormat {
      return preparedEngine
    }
    let preparedEngine = try PreparedAudioEngine.prepare()
    self.preparedEngine = preparedEngine
    return preparedEngine
  }
}
