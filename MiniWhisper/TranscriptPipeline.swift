import AppSettings
import ASREngine
import AudioCapture
import ComposableArchitecture
import FieldContext
import Foundation
import History
import ModelLibrary
import OSLog
import TranscriptCleanup

private let pipelineLogger = Logger(
  subsystem: "com.thurstonsand.MiniWhisper", category: "pipeline",
)

// MARK: - CleanupConditioning

/// Everything the cleanup pass reads besides the transcript: the field the words were meant for,
/// the vocabulary they must not be corrected out of, and the application they were bound for. A
/// dictation captures it at delivery time; a re-transcription reads the same three facts back off
/// the entry, which is why the entry persists them.
struct CleanupConditioning: Equatable {
  var fieldContext: FocusedTextContext?
  var vocabulary: [String]
  var targetBundleID: String?
}

// MARK: - CleanupResolution

/// How the cleanup leg ended. A pass-through means there was never a request; everything else
/// carries the configuration it was attempted against, because a resolution that could not say
/// what it ran on would need one handed to it at every point it is read.
enum CleanupResolution: Equatable {
  case passedThrough
  case attempted(CleanupConfiguration, Attempt)

  // MARK: Internal

  enum Attempt: Equatable {
    case cleaned(String, seconds: Double)
    case skipped(seconds: Double)
    /// `rejectsKey` is the endpoint refusing the key it was sent, which outlives the dictation:
    /// the key reads invalid until a cleanup with it succeeds.
    case failed(reason: String, seconds: Double, rejectsKey: Bool)
  }
}

// MARK: - CleanupPlan

/// Whether a pass can run at all — the settings and the Keychain answering together, in that
/// order, because an unconfigured pane never has a key to look for.
enum CleanupPlan: Equatable {
  /// Disabled, unfinished in the pane, or a factory profile without its key: the pipeline is a
  /// pass-through.
  case nothingToRun
  case keyUnreadable(CleanupConfiguration)
  /// A nil key is Custom pointed at an endpoint that takes none.
  case runnable(CleanupConfiguration, apiKey: String?)
  case local(CleanupConfiguration)
}

// MARK: - ProcessedTranscript

/// One recording's processing, whole: what the engine heard, and what cleanup made of it. The
/// record is absent whenever no pass ran — there is nothing to attribute.
struct ProcessedTranscript: Equatable {
  var outcome: TranscriptionOutcome
  var cleanup: CleanupRecord?
}

// MARK: - TranscriptPipeline

/// What every recording goes through, in the order it always goes through it: the engine, then
/// the cleanup pass over what the engine heard.
///
/// A live dictation runs the legs one at a time, because between them it has a pill to move and
/// an activation press to answer. A re-transcription has neither and runs `process`. Both reach
/// the cleanup leg through `resolveCleanup`, so the two cannot drift apart.
struct TranscriptPipeline {
  // MARK: Internal

  @Dependency(\.asrEngine) var asrEngine
  @Dependency(\.cleanup) var cleanupClient
  @Dependency(\.date) var date
  @Dependency(\.keychain) var keychain
  @Dependency(\.modelLibrary) var modelLibrary

  func transcribe(
    _ recording: CanonicalRecording, engine: SpeechEngine, dictionary: TranscriptionDictionary,
  ) async throws -> TranscriptionOutcome {
    try await asrEngine.submit(engine, recording, dictionary)
  }

  func plan(_ target: CleanupTarget?) -> CleanupPlan {
    guard let target else {
      return .nothingToRun
    }
    let configuration = target.configuration
    // A local model that is not on disk is the same unfinished configuration a missing key is.
    guard let credential = target.credential else {
      return modelLibrary.isInstalled(.s1Mini) ? .local(configuration) : .nothingToRun
    }
    let apiKey: String?
    do {
      apiKey = try keychain.read(credential)
    } catch {
      pipelineLogger.error(
        "Cleanup key unreadable: \(error.localizedDescription, privacy: .public)",
      )
      return .keyUnreadable(configuration)
    }
    // Custom's key is optional: only a configuration that verified is ever stored, so a keyless
    // one is an endpoint that answered without a key. A factory profile's missing key is the
    // degradation that already stopped this dictation from starting.
    guard apiKey != nil || credential.provider == .endpoint else {
      return .nothingToRun
    }
    return .runnable(configuration, apiKey: apiKey)
  }

  /// The cleanup leg, whole: plan it, and either run it or say why it never became a request.
  /// `requestStarting` runs if and only if one is about to leave, which is what lets a live
  /// dictation move its pill and arm its skip only for a pass that is really happening.
  ///
  /// Nil is cancellation: whoever cancelled has already resolved whatever was waiting.
  func resolveCleanup(
    _ transcript: String, conditioning: CleanupConditioning, target: CleanupTarget?,
    requestStarting: (CleanupConfiguration) async -> Void = { _ in },
  ) async -> CleanupResolution? {
    switch plan(target) {
    case .nothingToRun:
      return .passedThrough
    // A key the Keychain refuses is a cleanup failure and says so. No request leaves, so the
    // pill never flashes a phase that is not happening.
    case let .keyUnreadable(configuration):
      return .attempted(
        configuration,
        .failed(reason: "keyUnreadable", seconds: 0, rejectsKey: false),
      )
    case let .runnable(configuration, apiKey):
      await requestStarting(configuration)
      return await clean(
        transcript, conditioning: conditioning, configuration: configuration, apiKey: apiKey,
      )
    case let .local(configuration):
      await requestStarting(configuration)
      let started = date.now
      let outcome = await cleanupClient.cleanLocally(transcript, configuration.timeout)
      return resolution(outcome, configuration: configuration, started: started)
    }
  }

  /// One request, timed and attributed. Nil is cancellation.
  func clean(
    _ transcript: String, conditioning: CleanupConditioning,
    configuration: CleanupConfiguration, apiKey: String?,
  ) async -> CleanupResolution? {
    let request = CleanupRequest(
      transcript: transcript, focusedTextContext: conditioning.fieldContext,
      vocabulary: conditioning.vocabulary, targetBundleID: conditioning.targetBundleID,
    )
    let started = date.now
    let outcome = await cleanupClient.clean(request, configuration, apiKey)
    return resolution(outcome, configuration: configuration, started: started)
  }

  /// The unattended run: nothing can interrupt it, so both legs happen here and the caller is
  /// handed one transcription's worth of result.
  func process(
    _ recording: CanonicalRecording, engine: SpeechEngine, dictionary: TranscriptionDictionary,
    conditioning: CleanupConditioning, target: CleanupTarget?,
  ) async throws -> ProcessedTranscript {
    let outcome = try await transcribe(recording, engine: engine, dictionary: dictionary)
    guard case let .transcript(transcript) = outcome else {
      return ProcessedTranscript(outcome: outcome, cleanup: nil)
    }
    let resolution = await resolveCleanup(
      transcript, conditioning: conditioning, target: target,
    )
    return ProcessedTranscript(outcome: outcome, cleanup: resolution.flatMap(CleanupRecord.init))
  }

  // MARK: Private

  /// Nil is cancellation.
  private func resolution(
    _ outcome: CleanupOutcome, configuration: CleanupConfiguration, started: Date,
  ) -> CleanupResolution? {
    let seconds = date.now.timeIntervalSince(started)
    switch outcome {
    case let .cleaned(cleaned):
      pipelineLogger.notice("Cleaned in \(seconds, format: .fixed(precision: 2))s")
      return .attempted(configuration, .cleaned(cleaned, seconds: seconds))
    case .cancelled:
      return nil
    case let .failed(failure):
      pipelineLogger.error("Cleanup failed: \(failure.localizedDescription, privacy: .public)")
      return .attempted(configuration, .failed(
        reason: failure.historyDetail, seconds: seconds, rejectsKey: failure.rejectsKey,
      ))
    }
  }
}
