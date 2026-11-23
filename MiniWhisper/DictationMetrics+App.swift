import AppSettings
import ASREngine
import AudioCapture
import FieldContext
import Foundation
import History
import Metrics
import TranscriptCleanup

// MARK: - DictationMetrics + dictation

/// Where the app's text-bearing types meet the metrics record, which takes only their shape.
extension DictationMetrics {
  static func dictation(
    _ dictation: AppFeature.PendingDictation, id: UUID?, outcome: Outcome, finishedAt: Date,
    detached: Bool, delivery: History.Delivery?, vocabulary: Int,
  ) -> Self {
    let transcribedAt = dictation.original?.transcribedAt
    let cleanupSeconds: Double? =
      switch dictation.cleanupResolution {
      case let .attempted(_, .cleaned(_, _, seconds)),
           let .attempted(_, .skipped(seconds)),
           let .attempted(_, .failed(_, seconds)):
        seconds
      case .passedThrough,
           nil:
        nil
      }
    return DictationMetrics(
      at: dictation.createdAt, id: id, pass: 0, kind: .dictation, outcome: outcome,
      profile: dictation.profile.rawValue,
      engine: Self.model(dictation.engine, host: dictation.engineHost),
      engineHost: dictation.engineHost,
      audioSeconds: dictation.recording.durationSeconds,
      gesture: Gesture(
        mode: dictation.latched ? .latch : .hold, submit: dictation.submits, detached: detached,
      ),
      ms: Timings(
        stop: Timings.milliseconds(from: dictation.releasedAt, to: dictation.createdAt),
        transcribe: Timings.milliseconds(from: dictation.createdAt, to: transcribedAt),
        context: Timings.milliseconds(from: transcribedAt, to: dictation.contextCapturedAt),
        cleanupWait: Timings.milliseconds(
          from: dictation.contextCapturedAt, to: dictation.cleanupStartedAt,
        ),
        cleanup: Timings.milliseconds(cleanupSeconds),
        deliver: Timings.milliseconds(from: dictation.deliveryStartedAt, to: finishedAt),
        total: Timings.milliseconds(from: dictation.releasedAt, to: finishedAt),
      ),
      target: dictation.target.map(Target.init),
      field: dictation.capture.map(Field.init),
      screen: Screen(
        mode: dictation.screenMode.rawValue, context: dictation.screenContext,
        jpegBytes: dictation.screenCapture?.cleanupScreenshot?.count,
      ),
      cleanup: Cleanup(dictation.cleanupResolution, vocabulary: vocabulary),
      text: dictation.original.map {
        Text(raw: $0.text, cleaned: dictation.cleanupRecord?.cleanedText, delivered: delivery?.text)
      },
      // Every History detail is one fixed token, except a non-text element's, which goes on to
      // name the role the target app reported; the line keeps the token alone.
      delivery: delivery.map {
        Delivery(
          method: $0.method.rawValue,
          detail: $0.detail.map { String($0.prefix { !$0.isWhitespace }) },
        )
      },
    )
  }

  static func retranscription(
    of entry: HistoryEntry, pass: Int?, outcome: Outcome, at: Date, profile: ProfileID,
    engine: String, engineHost: String?, processed: ProcessedTranscript?, vocabulary: Int,
  ) -> Self {
    let cleanupSeconds: Double? =
      switch processed?.cleanupResolution {
      case let .attempted(_, .cleaned(_, _, seconds)),
           let .attempted(_, .skipped(seconds)),
           let .attempted(_, .failed(_, seconds)):
        seconds
      case .passedThrough,
           nil:
        nil
      }
    var raw: String?
    if let heard = processed?.outcome, case let TranscriptionOutcome.transcript(text) = heard {
      raw = text
    }
    return DictationMetrics(
      at: at, id: entry.id, pass: pass, kind: .retranscription, outcome: outcome,
      profile: profile.rawValue, engine: model(engine, host: engineHost), engineHost: engineHost,
      audioSeconds: entry.audio?.durationSeconds,
      gesture: nil,
      ms: Timings(
        transcribe: Timings.milliseconds(processed?.transcriptionSeconds),
        cleanup: Timings.milliseconds(cleanupSeconds),
      ),
      target: nil,
      field: entry.fieldContext.map { Field(.available($0)) },
      screen: entry.screenshot?.shownToCleanup == true
        ? Screen(mode: nil, context: nil, jpegBytes: entry.screenshot?.byteCount)
        : Screen(mode: nil, context: entry.screenContext, jpegBytes: nil),
      cleanup: Cleanup(processed?.cleanupResolution, vocabulary: vocabulary),
      text: raw.map { Text(raw: $0, cleaned: processed?.cleanup?.cleanedText, delivered: nil) },
      delivery: nil,
    )
  }
}

private extension DictationMetrics {
  /// An overridden engine's identity is `host/model`; the line keeps them apart.
  static func model(_ identity: String, host: String?) -> String {
    guard let host, identity.hasPrefix("\(host)/") else {
      return identity
    }
    return String(identity.dropFirst(host.count + 1))
  }
}

// MARK: - Stages

extension DictationMetrics.Target {
  init(_ target: DeliveryTarget) {
    let kind: Kind =
      if target.pane != nil {
        .tmux
      } else if target.terminal != nil {
        .ghostty
      } else if target.app != nil {
        .gui
      } else {
        .none
      }
    self.init(kind: kind, bundle: target.app?.bundleID)
  }
}

extension DictationMetrics.Field {
  init(_ capture: ContextCapture) {
    switch capture {
    case let .available(context):
      self.init(
        outcome: "available",
        chars: context.before.count + context.selected.count + context.after.count,
      )
    case let .unavailable(reason):
      self.init(outcome: reason.metricsName, chars: nil)
    }
  }
}

extension ContextUnavailable {
  /// The case alone: an associated role or bundle ID is a detail the line already has elsewhere.
  var metricsName: String {
    switch self {
    case .accessibilityPermissionMissing:
      "accessibilityPermissionMissing"
    case .noFocusedElement:
      "noFocusedElement"
    case .nonTextElement:
      "nonTextElement"
    case .noTextRange:
      "noTextRange"
    case .gridSemantics:
      "gridSemantics"
    case .zeroWidthSink:
      "zeroWidthSink"
    case .protectedField:
      "protectedField"
    case .axFailure:
      "axFailure"
    case .timedOut:
      "timedOut"
    }
  }
}

extension DictationMetrics.Screen {
  init(mode: String?, context: ScreenContext?, jpegBytes: Int?) {
    let text = context?.visibleText.flatMap { $0.isEmpty ? nil : $0 }
    let source: String? =
      if text == nil {
        nil
      } else if let structured = context?.structured {
        structured.source.rawValue
      } else {
        "ocr"
      }
    self.init(
      mode: mode,
      captured: jpegBytes != nil ? .screenshot : text != nil ? .text : .none,
      source: source, textChars: text?.count, jpegBytes: jpegBytes,
    )
  }
}

extension DictationMetrics.Cleanup {
  /// Nil when no pass was attempted.
  init?(_ resolution: CleanupResolution?, vocabulary: Int) {
    guard case let .attempted(configuration, attempt) = resolution else {
      return nil
    }
    let disposition: Disposition
    var stripped: [String]?
    var failure: CleanupFailure?
    switch attempt {
    case let .cleaned(_, wrappers, _):
      disposition = .cleaned
      stripped = wrappers.map(\.rawValue)
    case .skipped:
      disposition = .skipped
    case let .failed(reason, _):
      disposition = .failed
      failure = reason
    }
    let httpStatus: Int? =
      if case let .httpStatus(code, _) = failure {
        code
      } else {
        nil
      }
    self.init(
      model: configuration.model, host: configuration.endpoint.host(),
      effort: configuration.reasoningEffort.rawValue, disposition: disposition,
      failure: failure?.metricsName, httpStatus: httpStatus, stripped: stripped,
      instructionsChars: configuration.additionalInstructions
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .count,
      vocabulary: vocabulary,
    )
  }
}

extension CleanupFailure {
  /// The kind of failure, never its message: an endpoint's error text can quote the request.
  var metricsName: String {
    switch self {
    case .unreachable:
      "unreachable"
    case .httpStatus:
      "http"
    case .timedOut:
      "timed_out"
    case .malformedResponse:
      "malformed"
    case .degenerateResponse(.empty):
      "degenerate_empty"
    case .degenerateResponse(.runaway):
      "degenerate_runaway"
    case .localModel:
      "local_model"
    case .keyUnreadable:
      "key_unreadable"
    }
  }
}

// MARK: - HistoryLog + metrics

extension HistoryLog {
  /// Every transcription History still has, keyed the way metrics lines name their pass.
  var metricsTranscripts: [MetricsLog.PassKey: MetricsLog.Transcripts] {
    var transcripts: [MetricsLog.PassKey: MetricsLog.Transcripts] = [:]
    for entry in entries {
      if let original = entry.original {
        transcripts[.init(id: entry.id, pass: 0)] = .init(
          raw: original.text, cleaned: original.cleanup?.cleanedText,
          delivered: entry.delivery?.text,
        )
      }
      for (index, rerun) in entry.retranscriptions.enumerated() {
        transcripts[.init(id: entry.id, pass: index + 1)] = .init(
          raw: rerun.text, cleaned: rerun.cleanup?.cleanedText, delivered: nil,
        )
      }
    }
    return transcripts
  }
}
