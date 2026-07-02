import AudioCapture
import Testing

@testable import MiniWhisper

// MARK: - Test Doubles

@MainActor
final class StubMicPermissionProvider: MicPermissionProviding, @unchecked Sendable {
  private var currentStatus: MicPermissionStatus
  private let requestResult: MicPermissionStatus
  private(set) var requestCallCount = 0

  nonisolated var status: MicPermissionStatus {
    MainActor.assumeIsolated { currentStatus }
  }

  init(status: MicPermissionStatus, requestResult: MicPermissionStatus? = nil) {
    self.currentStatus = status
    self.requestResult = requestResult ?? status
  }

  func request() async -> MicPermissionStatus {
    requestCallCount += 1
    currentStatus = requestResult
    return requestResult
  }
}

// MARK: - RecordingStore Permission Tests

@MainActor
@Suite
struct RecordingStorePermissionTests {
  @Test
  func initializesWithProviderStatus() {
    let provider = StubMicPermissionProvider(status: .granted)
    let store = RecordingStore(permissionProvider: provider)
    #expect(store.micStatus == .granted)
  }

  @Test
  func initializesWithUndeterminedStatus() {
    let provider = StubMicPermissionProvider(status: .undetermined)
    let store = RecordingStore(permissionProvider: provider)
    #expect(store.micStatus == .undetermined)
  }

  @Test
  func requestMicAccessUpdatesStatus() async {
    let provider = StubMicPermissionProvider(status: .undetermined, requestResult: .granted)
    let store = RecordingStore(permissionProvider: provider)
    #expect(store.micStatus == .undetermined)

    await store.requestMicAccess()

    #expect(store.micStatus == .granted)
    #expect(provider.requestCallCount == 1)
  }

  @Test
  func requestMicAccessCanBeDenied() async {
    let provider = StubMicPermissionProvider(status: .undetermined, requestResult: .denied)
    let store = RecordingStore(permissionProvider: provider)

    await store.requestMicAccess()

    #expect(store.micStatus == .denied)
  }
}

// MARK: - RecordingStore Recording State Tests

@MainActor
@Suite
struct RecordingStoreRecordingTests {
  @Test
  func startsInIdleState() {
    let provider = StubMicPermissionProvider(status: .granted)
    let store = RecordingStore(permissionProvider: provider)
    #expect(store.status == .idle)
  }

  @Test
  func startRecordingTransitionsToRecording() {
    let provider = StubMicPermissionProvider(status: .granted)
    let store = RecordingStore(permissionProvider: provider)

    store.startRecording()

    #expect(store.status == .recording)
  }

  @Test
  func startRecordingRequiresGrantedPermission() {
    let provider = StubMicPermissionProvider(status: .denied)
    let store = RecordingStore(permissionProvider: provider)

    store.startRecording()

    #expect(store.status == .idle)
  }

  @Test
  func stopRecordingTransitionsToProcessing() {
    let provider = StubMicPermissionProvider(status: .granted)
    let store = RecordingStore(permissionProvider: provider)
    store.startRecording()

    store.stopRecording()

    #expect(store.status == .processing)
  }

  @Test
  func stopRecordingOnlyWorksWhenRecording() {
    let provider = StubMicPermissionProvider(status: .granted)
    let store = RecordingStore(permissionProvider: provider)

    store.stopRecording()

    #expect(store.status == .idle)
  }

  @Test
  func resetClearsAllState() {
    let provider = StubMicPermissionProvider(status: .granted)
    let store = RecordingStore(permissionProvider: provider)
    store.startRecording()

    store.reset()

    #expect(store.status == .idle)
    #expect(store.audioLevel == 0)
    #expect(store.currentTranscription == nil)
    #expect(store.lastError == nil)
  }
}

// MARK: - Icon Selection Tests

@Suite
struct IconSelectionTests {
  @Test
  func recordingShowsRecordIcon() {
    let symbol = iconSymbolName(status: RecordingStatus.recording, micStatus: MicPermissionStatus.granted)
    #expect(symbol == "record.circle.fill")
  }

  @Test
  func processingShowsEllipsisIcon() {
    let symbol = iconSymbolName(status: RecordingStatus.processing, micStatus: MicPermissionStatus.granted)
    #expect(symbol == "ellipsis.circle")
  }

  @Test
  func idleWithMicGrantedShowsWaveform() {
    let symbol = iconSymbolName(status: RecordingStatus.idle, micStatus: MicPermissionStatus.granted)
    #expect(symbol == "waveform")
  }

  @Test
  func idleWithMicDeniedShowsWarningIcon() {
    let symbol = iconSymbolName(status: RecordingStatus.idle, micStatus: MicPermissionStatus.denied)
    #expect(symbol == "waveform.badge.exclamationmark")
  }

  @Test
  func idleWithMicUndeterminedShowsWarningIcon() {
    let symbol = iconSymbolName(status: RecordingStatus.idle, micStatus: MicPermissionStatus.undetermined)
    #expect(symbol == "waveform.badge.exclamationmark")
  }
}
