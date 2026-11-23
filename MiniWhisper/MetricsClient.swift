import ComposableArchitecture
import Foundation
import Metrics
import OSLog

private let metricsLogger = Logger(subsystem: "com.thurstonsand.MiniWhisper", category: "metrics")

// MARK: - MetricsClient

@DependencyClient struct MetricsClient {
  var record: @Sendable (DictationMetrics) async -> Void
  /// Writes a copy of the log at `detail` beside the app's other files, and answers where.
  var export: @Sendable (
    _ detail: MetricsLog.ExportDetail,
    _ transcripts: [MetricsLog.PassKey: MetricsLog.Transcripts],
  ) async throws -> URL
}

// MARK: DependencyKey

extension MetricsClient: DependencyKey {
  static let testValue = Self(record: { _ in }, export: { _, _ in Channel.metricsExportDirectory })

  static let liveValue: Self = {
    let writer = MetricsWriter(log: MetricsLog(url: Channel.metricsFile))
    return Self(
      record: { await writer.record($0) },
      export: { try await writer.export($0, transcripts: $1) },
    )
  }()
}

extension DependencyValues {
  var metrics: MetricsClient {
    get { self[MetricsClient.self] }
    set { self[MetricsClient.self] = newValue }
  }
}

// MARK: - MetricsWriter

/// Serialises the log's appends and exports. A line that cannot be written is logged and lost:
/// metrics never stand in the way of a dictation.
private actor MetricsWriter {
  // MARK: Lifecycle

  init(log: MetricsLog) {
    self.log = log
  }

  // MARK: Internal

  func record(_ metrics: DictationMetrics) {
    do {
      try log.append(metrics)
    } catch {
      metricsLogger.error("Metrics line unwritten: \(error.localizedDescription, privacy: .public)")
    }
  }

  func export(
    _ detail: MetricsLog.ExportDetail,
    transcripts: [MetricsLog.PassKey: MetricsLog.Transcripts],
  ) throws -> URL {
    let data = try MetricsLog.export(log.read(), detail: detail, transcripts: transcripts)
    let stamp = Date.now
      .formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
      .replacing(":", with: "")
    let url = Channel.metricsExportDirectory.appending(
      path: "metrics-\(stamp)-\(detail.rawValue).jsonl",
    )
    try FileManager.default.createDirectory(
      at: Channel.metricsExportDirectory, withIntermediateDirectories: true,
    )
    try data.write(to: url, options: .atomic)
    return url
  }

  // MARK: Private

  private let log: MetricsLog
}
