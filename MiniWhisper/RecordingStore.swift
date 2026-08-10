import AppSettings
import AudioCapture
import ComposableArchitecture
import Foundation
import OSLog

private let captureLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "capture")
private let performanceLogger = Logger(
  subsystem: "com.thurstonsand.MiniWhisper", category: "performance",
)

// MARK: - RecordingFeature

@Reducer struct RecordingFeature {
  // MARK: Internal

  @ObservableState struct State: Equatable {
    // MARK: Lifecycle

    init(settings: Shared<MiniWhisperSettings>, health: Shared<AppHealth>) {
      _settings = settings
      _health = health
    }

    // MARK: Internal

    enum Phase: Equatable {
      case idle
      case starting(PendingCompletion?)
      case recording
      case stopping(PendingRestart?)
      case cancelling
    }

    enum PendingCompletion: Equatable { case stop, cancel }
    enum PendingRestart: Equatable { case restart }

    @Shared var settings: MiniWhisperSettings
    @Shared var health: AppHealth
    var phase = Phase.idle
    var latestLevel: Float = 0
    var captureError: AudioCaptureError?
    var captureGeneration = 0
    var captureSessionID: UUID?
  }

  enum Action: Equatable {
    case task
    case microphoneChanged(MicrophoneSelection)
    case capturePreparationFailed(AudioCaptureError)
    case startRecording
    case stopAndRetain
    case cancelRecording
    case captureSessionStarted(Int, UUID)
    case captureBecameLive(Int, UUID, String)
    case levelUpdated(Int, AudioLevel)
    case captureFailed(Int, AudioCaptureError)
    case captureEventsFinished(Int)
    case captureStopped(Int, CanonicalRecording)
    case captureCancelled(Int)
    case delegate(Delegate)

    // MARK: Internal

    enum Delegate: Equatable {
      case recordingStarted(inputDeviceName: String)
      case levelChanged(Float)
      case completed(CanonicalRecording)
      case discarded
      case failed
    }
  }

  @Dependency(\.audioCapture) var audioCapture

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case .task:
        return prepareCapture(selection: state.settings.microphone)
      case let .microphoneChanged(selection):
        return prepareCapture(selection: selection)
      case let .capturePreparationFailed(error):
        state.captureError = error
        captureLogger.error(
          "Audio capture preparation failed: \(error.localizedDescription, privacy: .public)",
        )
        return .none
      case .startRecording:
        switch state.phase {
        case .idle:
          performanceLogger.notice("benchmark capture-start-requested")
          state.captureGeneration += 1
          state.captureSessionID = nil
          state.phase = .starting(nil)
          state.latestLevel = 0
          state.captureError = nil
          return startCapture(
            generation: state.captureGeneration, selection: state.settings.microphone,
          )
        case .starting(.stop):
          state.phase = .starting(nil)
          return .none
        case .stopping:
          state.phase = .stopping(.restart)
          return .none
        case .starting,
             .recording,
             .cancelling:
          return .none
        }
      case .stopAndRetain:
        switch state.phase {
        case .starting(.cancel):
          return .none
        case .starting:
          guard let sessionID = state.captureSessionID else {
            state.phase = .starting(.stop)
            return .none
          }
          return completeStarting(&state, .stop, sessionID: sessionID)
        case .recording:
          guard let sessionID = state.captureSessionID else {
            return missingSessionFailure(generation: state.captureGeneration)
          }
          state.phase = .stopping(nil)
          return stopCapture(generation: state.captureGeneration, sessionID: sessionID)
        case .idle,
             .stopping,
             .cancelling:
          return .none
        }
      case .cancelRecording:
        switch state.phase {
        case .starting:
          guard let sessionID = state.captureSessionID else {
            state.phase = .starting(.cancel)
            return .send(.delegate(.discarded))
          }
          return .concatenate(
            .send(.delegate(.discarded)),
            completeStarting(&state, .cancel, sessionID: sessionID),
          )
        case .recording,
             .stopping:
          guard let sessionID = state.captureSessionID else {
            return missingSessionFailure(generation: state.captureGeneration)
          }
          state.phase = .cancelling
          return .concatenate(
            .send(.delegate(.discarded)),
            .merge(
              .cancel(id: CancelID.stop),
              cancelCapture(generation: state.captureGeneration, sessionID: sessionID),
            ),
          )
        case .idle,
             .cancelling:
          return .none
        }
      case let .captureSessionStarted(generation, sessionID):
        guard generation == state.captureGeneration,
              case let .starting(pendingCompletion) = state.phase
        else {
          return cancelCapture(generation: generation, sessionID: sessionID)
        }

        state.captureSessionID = sessionID
        guard let pendingCompletion else {
          return .none
        }
        return completeStarting(&state, pendingCompletion, sessionID: sessionID)
      case let .captureBecameLive(generation, sessionID, inputDeviceName):
        // A pending completion is always spent the moment the session ID lands, so a capture that
        // reaches this point is one nobody has asked to end.
        guard generation == state.captureGeneration, state.captureSessionID == sessionID,
              state.phase == .starting(nil)
        else {
          return .none
        }

        state.phase = .recording
        captureLogger.notice("Audio capture became live")
        return .send(.delegate(.recordingStarted(inputDeviceName: inputDeviceName)))
      case let .levelUpdated(generation, level):
        guard generation == state.captureGeneration else {
          return .none
        }
        switch state.phase {
        case .recording,
             .stopping:
          state.latestLevel = level.normalizedPower
          return .send(.delegate(.levelChanged(level.normalizedPower)))
        case .idle,
             .starting,
             .cancelling:
          return .none
        }
      case let .captureFailed(generation, error):
        guard generation == state.captureGeneration, state.phase != .idle,
              state.phase != .cancelling
        else {
          return .none
        }

        state.phase = .cancelling
        state.latestLevel = 0
        state.captureError = error
        if case let .microphonePermission(status) = error {
          state.$health.withLock { $0.micStatus = status }
        }
        captureLogger.error("Audio capture failed: \(error.localizedDescription, privacy: .public)")

        let cleanup: Effect<Action> =
          if let sessionID = state.captureSessionID {
            cancelCapture(generation: generation, sessionID: sessionID)
          } else {
            .send(.captureCancelled(generation))
          }
        return .concatenate(.send(.delegate(.failed)), cleanup)
      case let .captureEventsFinished(generation):
        guard generation == state.captureGeneration else {
          return .none
        }
        switch state.phase {
        case .starting,
             .recording:
          return .send(.captureFailed(generation, .unexpected("Audio capture event stream ended")))
        case .idle,
             .stopping,
             .cancelling:
          return .none
        }
      case let .captureStopped(generation, recording):
        guard generation == state.captureGeneration,
              case let .stopping(pendingRestart) = state.phase
        else {
          return .none
        }
        state.captureSessionID = nil
        state.latestLevel = 0
        if pendingRestart == .restart {
          state.captureGeneration += 1
          state.phase = .starting(nil)
          captureLogger.notice("Restarting audio capture for latch")
          return startCapture(
            generation: state.captureGeneration, selection: state.settings.microphone,
          )
        }

        state.phase = .idle
        captureLogger.notice(
          "Audio capture stopped duration=\(recording.durationSeconds, format: .fixed(precision: 3))s samples=\(recording.samples.count)",
        )
        return .send(.delegate(.completed(recording)))
      case let .captureCancelled(generation):
        guard generation == state.captureGeneration, state.phase == .cancelling else {
          return .none
        }
        state.captureSessionID = nil
        state.phase = .idle
        state.latestLevel = 0
        captureLogger.notice("Audio capture cancelled and discarded")
        return .none
      case .delegate:
        return .none
      }
    }
  }

  // MARK: Private

  private enum CancelID { case captureEvents, preparation, stop }

  /// A completion asked for during `.starting` runs at whichever moment the session ID is known:
  /// here if it has already arrived, otherwise when `captureSessionStarted` delivers it. Waiting
  /// for the capture to go live instead would strand a device that never produces a buffer.
  private func completeStarting(
    _ state: inout State, _ completion: State.PendingCompletion, sessionID: UUID,
  ) -> Effect<Action> {
    switch completion {
    case .stop:
      state.phase = .stopping(nil)
      return stopCapture(generation: state.captureGeneration, sessionID: sessionID)
    case .cancel:
      state.phase = .cancelling
      return cancelCapture(generation: state.captureGeneration, sessionID: sessionID)
    }
  }

  /// Cancellation drops the reply, not the actor call already in flight, which is all this needs:
  /// prewarming is a hint, and rapid switching just leaves the cache on the last selection asked
  /// for. What it does prevent is a superseded failure reporting against the current device.
  private func prepareCapture(selection: MicrophoneSelection) -> Effect<Action> {
    .run { send in
      do { try await audioCapture.prepare(selection) } catch {
        await send(.capturePreparationFailed(captureError(from: error)))
      }
    }.cancellable(id: CancelID.preparation, cancelInFlight: true)
  }

  private func startCapture(
    generation: Int, selection: MicrophoneSelection,
  ) -> Effect<Action> {
    let cancellation = CaptureCancellation()
    return .run { send in
      await withTaskCancellationHandler {
        do {
          let session = try await audioCapture.start(selection)
          if cancellation.setSessionID(session.id) {
            await audioCapture.cancel(session.id)
            return
          }
          await send(.captureSessionStarted(generation, session.id))

          var summary = LevelSummary()
          var summaryStartedAt = ContinuousClock.now
          for await event in session.events {
            switch event {
            case .captureBecameLive:
              await send(.captureBecameLive(generation, session.id, session.inputDeviceName))
            case let .level(level):
              await send(.levelUpdated(generation, level))
              summary.add(level)
              let now = ContinuousClock.now
              if summaryStartedAt.duration(to: now) >= .seconds(1) {
                summary.log()
                summary = LevelSummary()
                summaryStartedAt = now
              }
            case let .failed(error):
              await send(.captureFailed(generation, error))
            }
          }
          summary.log()
          await send(.captureEventsFinished(generation))
        } catch { await send(.captureFailed(generation, captureError(from: error))) }
      } onCancel: {
        guard let sessionID = cancellation.cancel() else {
          return
        }
        Task { await audioCapture.cancel(sessionID) }
      }
    }.cancellable(id: CancelID.captureEvents, cancelInFlight: true)
  }

  private func stopCapture(generation: Int, sessionID: UUID) -> Effect<Action> {
    .run { send in
      do { try await send(.captureStopped(generation, audioCapture.stop(sessionID))) } catch {
        await send(.captureFailed(generation, captureError(from: error)))
      }
    }.cancellable(id: CancelID.stop, cancelInFlight: true)
  }

  private func cancelCapture(generation: Int, sessionID: UUID) -> Effect<Action> {
    .run { send in
      await audioCapture.cancel(sessionID)
      await send(.captureCancelled(generation))
    }
  }

  private func missingSessionFailure(generation: Int) -> Effect<Action> {
    .send(.captureFailed(generation, .unexpected("Capture state has no session identifier")))
  }
}

// MARK: - CaptureCancellation

private final class CaptureCancellation: @unchecked Sendable {
  // MARK: Internal

  func setSessionID(_ sessionID: UUID) -> Bool {
    lock.withLock {
      self.sessionID = sessionID
      return isCancelled
    }
  }

  func cancel() -> UUID? {
    lock.withLock {
      isCancelled = true
      return sessionID
    }
  }

  // MARK: Private

  private let lock = NSLock()
  private var isCancelled = false
  private var sessionID: UUID?
}

// MARK: - LevelSummary

private struct LevelSummary {
  // MARK: Internal

  mutating func add(_ level: AudioLevel) {
    minimum = min(minimum, level.normalizedPower)
    maximum = max(maximum, level.normalizedPower)
    total += level.normalizedPower
    count += 1
  }

  func log() {
    guard count > 0 else {
      return
    }
    captureLogger.info(
      "Audio level summary count=\(count) min=\(minimum, format: .fixed(precision: 2)) avg=\(total / Float(count), format: .fixed(precision: 2)) max=\(maximum, format: .fixed(precision: 2))",
    )
  }

  // MARK: Private

  private var minimum = Float.greatestFiniteMagnitude
  private var maximum = Float.zero
  private var total = Float.zero
  private var count = 0
}

private func captureError(from error: any Error) -> AudioCaptureError {
  if let error = error as? AudioCaptureError {
    return error
  }
  return .unexpected(error.localizedDescription)
}
