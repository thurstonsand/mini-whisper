import Foundation

// MARK: - ResumeDecision

enum ResumeDecision: Equatable {
  case append
  case overwrite
  case restart
  case reject(String)

  // MARK: Internal

  static func decide(
    resumeOffset: Int, expectedBytes: Int, statusCode: Int, contentRange: String?,
    contentLength: Int64,
  ) -> Self {
    if statusCode == 200 {
      guard
        contentLength == NSURLSessionTransferSizeUnknown || contentLength == Int64(expectedBytes)
      else {
        return .reject("Content-Length does not match the pinned file size")
      }
      return .overwrite
    }
    if statusCode == 206 {
      guard let range = HTTPContentRange(contentRange), range.start == resumeOffset,
            range.total == expectedBytes
      else {
        return resumeOffset > 0 ? .restart : .reject("invalid Content-Range")
      }
      return resumeOffset > 0 ? .append : .overwrite
    }
    if statusCode == 416 || (statusCode == 403 && resumeOffset > 0) {
      return .restart
    }
    return .reject("HTTP \(statusCode)")
  }
}

// MARK: - HTTPContentRange

struct HTTPContentRange: Equatable {
  // MARK: Lifecycle

  init?(_ value: String?) {
    guard let value, value.hasPrefix("bytes ") else {
      return nil
    }
    let sections = value.dropFirst("bytes ".count).split(
      separator: "/", omittingEmptySubsequences: false,
    )
    guard sections.count == 2, let total = Int(sections[1]) else {
      return nil
    }
    let bounds = sections[0].split(separator: "-", omittingEmptySubsequences: false)
    guard bounds.count == 2, let start = Int(bounds[0]), let end = Int(bounds[1]), start <= end,
          end < total
    else {
      return nil
    }
    self.start = start
    self.end = end
    self.total = total
  }

  // MARK: Internal

  let start: Int
  let end: Int
  let total: Int
}

// MARK: - ProgressDownloadError

enum ProgressDownloadError: Error, Equatable {
  case restartRequired
  case invalidResponse(String)
}

// MARK: - ProgressDownload

final class ProgressDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
  // MARK: Lifecycle

  init(
    configuration: URLSessionConfiguration, destination: URL, expectedBytes: Int, resumeOffset: Int,
    progress: @escaping @Sendable (Int) -> Void,
  ) {
    self.configuration = configuration
    self.destination = destination
    self.expectedBytes = expectedBytes
    self.resumeOffset = resumeOffset
    self.progress = progress
    transferredBytes = resumeOffset
    lastReportedBytes = resumeOffset
  }

  // MARK: Internal

  func download(from url: URL) async throws {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        var request = URLRequest(url: url)
        if resumeOffset > 0 {
          request.setValue("bytes=\(resumeOffset)-", forHTTPHeaderField: "Range")
        }
        let task = session.dataTask(with: request)
        let cancelled = lock.withLock {
          guard !isCancelled else {
            return true
          }
          self.continuation = continuation
          self.session = session
          self.task = task
          return false
        }
        guard !cancelled else {
          session.invalidateAndCancel()
          continuation.resume(throwing: CancellationError())
          return
        }
        task.resume()
      }
    } onCancel: {
      let task = self.lock.withLock {
        self.isCancelled = true
        return self.task
      }
      task?.cancel()
    }
  }

  func urlSession(
    _: URLSession, task _: URLSessionTask,
    willPerformHTTPRedirection _: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void,
  ) {
    var redirectedRequest = request
    if resumeOffset > 0 {
      // Hugging Face signs its CDN redirect for this exact header; dropping it produces HTTP 403.
      redirectedRequest.setValue("bytes=\(resumeOffset)-", forHTTPHeaderField: "Range")
    }
    completionHandler(redirectedRequest)
  }

  func urlSession(
    _: URLSession, dataTask _: URLSessionDataTask, didReceive response: URLResponse,
    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void,
  ) {
    guard let response = response as? HTTPURLResponse else {
      setResponseError(ProgressDownloadError.invalidResponse("non-HTTP response"))
      completionHandler(.cancel)
      return
    }
    let decision = ResumeDecision.decide(
      resumeOffset: resumeOffset, expectedBytes: expectedBytes, statusCode: response.statusCode,
      contentRange: response.value(forHTTPHeaderField: "Content-Range"),
      contentLength: response.expectedContentLength,
    )
    do {
      let handle: FileHandle
      switch decision {
      case .append:
        handle = try FileHandle(forWritingTo: destination)
        try handle.seekToEnd()
      case .overwrite:
        if !FileManager.default.fileExists(atPath: destination.path) {
          FileManager.default.createFile(atPath: destination.path, contents: nil)
        }
        handle = try FileHandle(forWritingTo: destination)
        try handle.truncate(atOffset: 0)
        lock.withLock {
          transferredBytes = 0
          lastReportedBytes = 0
        }
      case .restart:
        throw ProgressDownloadError.restartRequired
      case let .reject(message):
        throw ProgressDownloadError.invalidResponse(message)
      }
      lock.withLock { fileHandle = handle }
      progress(decision == .append ? resumeOffset : 0)
      completionHandler(.allow)
    } catch {
      setResponseError(error)
      completionHandler(.cancel)
    }
  }

  func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    do {
      let report = try lock.withLock { () -> Int? in
        guard responseError == nil, let fileHandle else {
          return nil
        }
        try fileHandle.write(contentsOf: data)
        transferredBytes += data.count
        guard transferredBytes - lastReportedBytes >= Self.reportIntervalBytes else {
          return nil
        }
        lastReportedBytes = transferredBytes
        return min(transferredBytes, expectedBytes)
      }
      if let report {
        progress(report)
      }
    } catch {
      setResponseError(error)
      dataTask.cancel()
    }
  }

  func urlSession(
    _ session: URLSession, task _: URLSessionTask, didCompleteWithError error: (any Error)?,
  ) {
    let completion = lock.withLock {
      let continuation = self.continuation
      let fileHandle = self.fileHandle
      let responseError = self.responseError
      self.continuation = nil
      self.fileHandle = nil
      self.task = nil
      self.session = nil
      return (continuation, fileHandle, responseError)
    }
    try? completion.1?.close()
    session.finishTasksAndInvalidate()
    guard let continuation = completion.0 else {
      return
    }
    if let responseError = completion.2 {
      continuation.resume(throwing: responseError)
    } else if let error {
      continuation.resume(throwing: error)
    } else {
      progress(expectedBytes)
      continuation.resume()
    }
  }

  // MARK: Private

  private static let reportIntervalBytes = 1_048_576

  private let configuration: URLSessionConfiguration
  private let destination: URL
  private let expectedBytes: Int
  private let resumeOffset: Int
  private let progress: @Sendable (Int) -> Void
  private let lock = NSLock()

  private var continuation: CheckedContinuation<Void, any Error>?
  private var task: URLSessionDataTask?
  private var session: URLSession?
  private var fileHandle: FileHandle?
  private var responseError: (any Error)?
  private var isCancelled = false
  private var transferredBytes: Int
  private var lastReportedBytes: Int

  private func setResponseError(_ error: any Error) {
    lock.withLock {
      if responseError == nil {
        responseError = error
      }
    }
  }
}
