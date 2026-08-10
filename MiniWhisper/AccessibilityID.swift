import AppSettings
import Foundation

// MARK: - SettingsSoundPart

/// The addressable pieces of one sound row. Naming them keeps the pane from spelling identifier
/// suffixes by hand, which is how a row and its paint state drift apart.
enum SettingsSoundPart {
  case row
  case rowState
  case picker
  case pickerState
  case preview

  // MARK: Internal

  var suffix: String {
    switch self {
    case .row:
      ""
    case .rowState:
      ".state"
    case .picker:
      ".picker"
    case .pickerState:
      ".picker.state"
    case .preview:
      ".preview"
    }
  }
}

// MARK: - AccessibilityID

enum AccessibilityID {
  static let menuStatusItem = "miniwhisper.menu.status-item"
  static let menuStatus = "miniwhisper.menu.status"
  static let menuCopyLastTranscript = "miniwhisper.menu.copy-last-transcript"
  static let menuSettings = "miniwhisper.menu.settings"
  static let menuAbout = "miniwhisper.menu.about"
  static let menuQuit = "miniwhisper.menu.quit"

  static let settingsWindow = "miniwhisper.settings.window"
  static let settingsSidebar = "miniwhisper.settings.sidebar"
  static let settingsSidebarSettings = "miniwhisper.settings.sidebar.settings"
  static let settingsSidebarHistory = "miniwhisper.settings.sidebar.history"
  static let settingsSidebarModel = "miniwhisper.settings.sidebar.model"
  static let settingsSidebarDictionary = "miniwhisper.settings.sidebar.dictionary"
  static let settingsSidebarCleanup = "miniwhisper.settings.sidebar.cleanup"
  static let settingsPlaceholder = "miniwhisper.settings.placeholder"
  static let settingsShortcutRow = "miniwhisper.settings.shortcut.activate"
  static let settingsShortcutRowState = "miniwhisper.settings.shortcut.activate.state"
  static let settingsShortcutSet = "miniwhisper.settings.shortcut.set"
  static let settingsShortcutMenu = "miniwhisper.settings.shortcut.menu"
  static let settingsShortcutRecording = "miniwhisper.settings.shortcut.recording"
  static let settingsShortcutRecordingError = "miniwhisper.settings.shortcut.recording.error"
  static let settingsMicrophoneRow = "miniwhisper.settings.microphone"
  static let settingsMicrophoneRowState = "miniwhisper.settings.microphone.state"
  static let settingsMicrophonePicker = "miniwhisper.settings.microphone.picker"
  static let settingsMicrophoneLevel = "miniwhisper.settings.microphone.level"
  static let settingsMicrophoneUnavailable = "miniwhisper.settings.microphone.unavailable"
  static let settingsSoundPlayback = "miniwhisper.settings.sound.playback"
  static let settingsLaunchAtLogin = "miniwhisper.settings.launch-at-login"
  static let settingsLaunchAtLoginState = "miniwhisper.settings.launch-at-login.state"
  /// A switch spends its own accessibility value on being on or off, so the one row whose ring
  /// does not hug its control has to report the ring somewhere else.
  static let settingsLaunchAtLoginRing = "miniwhisper.settings.launch-at-login.ring"
  static let historyCaption = "miniwhisper.history.caption"
  static let historyStorage = "miniwhisper.history.storage"
  static let historyStoragePopover = "miniwhisper.history.storage.popover"

  static let aboutWindow = "miniwhisper.about.window"
  static let aboutContent = "miniwhisper.about.content"
  static let aboutIcon = "miniwhisper.about.icon"
  static let aboutAppName = "miniwhisper.about.app-name"
  static let aboutVersion = "miniwhisper.about.version"
  static let aboutAttribution = "miniwhisper.about.attribution"
  static let aboutModelLink = "miniwhisper.about.model-link"
  static let aboutFluidAudioAttribution = "miniwhisper.about.fluid-audio-attribution"
  static let aboutFluidAudioLink = "miniwhisper.about.fluid-audio-link"
  static let aboutClose = "miniwhisper.about.close"

  static let onboardingWindow = "miniwhisper.onboarding.window"
  static let onboardingWelcome = "miniwhisper.onboarding.welcome"
  static let onboardingWelcomeTitle = "miniwhisper.onboarding.welcome.title"
  static let onboardingWelcomeSummary = "miniwhisper.onboarding.welcome.summary"
  static let onboardingWelcomeModelInfo = "miniwhisper.onboarding.welcome.model-info"
  static let onboardingDownloadModel = "miniwhisper.onboarding.download-model"
  static let onboardingWelcomeFailure = "miniwhisper.onboarding.welcome.failure"

  static let onboardingRail = "miniwhisper.onboarding.rail"
  static let onboardingRailBrand = "miniwhisper.onboarding.rail.brand"
  static let onboardingRailTagline = "miniwhisper.onboarding.rail.tagline"
  static let onboardingRailPermissions = "miniwhisper.onboarding.rail.permissions"
  static let onboardingRailShortcut = "miniwhisper.onboarding.rail.shortcut"
  static let onboardingRailModel = "miniwhisper.onboarding.rail.model"
  static let onboardingRailTryIt = "miniwhisper.onboarding.rail.try-it"

  static let onboardingPermissions = "miniwhisper.onboarding.permissions"
  static let onboardingPermissionsTitle = "miniwhisper.onboarding.permissions.title"
  static let onboardingPermissionsSummary = "miniwhisper.onboarding.permissions.summary"
  static let onboardingPermissionMicrophone = "miniwhisper.onboarding.permission.microphone"
  static let onboardingPermissionMicrophoneStatus =
    "miniwhisper.onboarding.permission.microphone.status"
  static let onboardingPermissionMicrophoneAction =
    "miniwhisper.onboarding.permission.microphone.action"
  static let onboardingPermissionAccessibility = "miniwhisper.onboarding.permission.accessibility"
  static let onboardingPermissionAccessibilityStatus =
    "miniwhisper.onboarding.permission.accessibility.status"
  static let onboardingPermissionAccessibilityAction =
    "miniwhisper.onboarding.permission.accessibility.action"
  static let onboardingPermissionsGuidance = "miniwhisper.onboarding.permissions.guidance"

  static let onboardingShortcut = "miniwhisper.onboarding.shortcut"
  static let onboardingShortcutTitle = "miniwhisper.onboarding.shortcut.title"
  static let onboardingShortcutSummary = "miniwhisper.onboarding.shortcut.summary"
  static let onboardingShortcutBinding = "miniwhisper.onboarding.shortcut.binding"
  static let onboardingShortcutBindingRing = "miniwhisper.onboarding.shortcut.binding.state"
  static let onboardingShortcutCaption = "miniwhisper.onboarding.shortcut.caption"
  static let onboardingShortcutError = "miniwhisper.onboarding.shortcut.error"
  static let onboardingShortcutContinue = "miniwhisper.onboarding.shortcut.continue"

  static let onboardingModel = "miniwhisper.onboarding.model"
  static let onboardingModelTitle = "miniwhisper.onboarding.model.title"
  static let onboardingModelSummary = "miniwhisper.onboarding.model.summary"
  static let onboardingModelStatus = "miniwhisper.onboarding.model.status"
  static let onboardingModelProgress = "miniwhisper.onboarding.model-progress"
  static let onboardingModelRetry = "miniwhisper.onboarding.model.retry"

  static let onboardingTryIt = "miniwhisper.onboarding.try-it"
  static let onboardingTryItTitle = "miniwhisper.onboarding.try-it.title"
  static let onboardingTryItInstructions = "miniwhisper.onboarding.try-it.instructions"
  static let onboardingTryItAvailability = "miniwhisper.onboarding.try-it.availability"
  static let onboardingTryItText = "miniwhisper.onboarding.try-it.text"
  static let onboardingTryItHotkey = "miniwhisper.onboarding.try-it.hotkey"
  static let onboardingTryItCompletion = "miniwhisper.onboarding.try-it.completion"
  static let onboardingTryItCompletionSummary = "miniwhisper.onboarding.try-it.completion-summary"
  static let onboardingTryItGuidance = "miniwhisper.onboarding.try-it.guidance"
  static let onboardingTryItSkip = "miniwhisper.onboarding.try-it.skip"
  static let onboardingTryItSkipRing = "miniwhisper.onboarding.try-it.skip.state"

  static let onboardingReady = "miniwhisper.onboarding.ready"
  static let onboardingReadyTitle = "miniwhisper.onboarding.ready.title"
  static let onboardingReadySummary = "miniwhisper.onboarding.ready.summary"
  static let onboardingReadyTranscript = "miniwhisper.onboarding.ready.transcript"
  static let onboardingReadyFinish = "miniwhisper.onboarding.ready.finish"
  static let onboardingFailure = "miniwhisper.onboarding.failure"

  static let pill = "miniwhisper.pill"
  static let pillPhase = "miniwhisper.pill.phase"
  static let pillCaptureStatus = "miniwhisper.pill.capture-status"
  static let pillInputDevice = "miniwhisper.pill.input-device"
  static let pillAudioLevel = "miniwhisper.pill.audio-level"
  static let pillNotice = "miniwhisper.pill.notice"

  static let settingsEngineStatus = "miniwhisper.settings.engine-status"

  static func menuRepair(_ degradation: Degradation) -> String {
    "miniwhisper.menu.repair.\(degradation.rawValue)"
  }

  static func settingsRepairRow(_ degradation: Degradation) -> String {
    "miniwhisper.settings.repair.\(degradation.rawValue)"
  }

  static func settingsRepairAction(_ degradation: Degradation) -> String {
    "\(settingsRepairRow(degradation)).action"
  }

  static func settingsShortcutBinding(_ index: Int) -> String {
    "miniwhisper.settings.shortcut.binding.\(index)"
  }

  static func settingsSound(_ cue: SoundCue, _ part: SettingsSoundPart) -> String {
    "miniwhisper.settings.sound.\(cue.slug)\(part.suffix)"
  }

  static func historyRow(_ id: UUID) -> String {
    "miniwhisper.history.row.\(id.uuidString)"
  }

  static func historyRowState(_ id: UUID) -> String {
    "miniwhisper.history.row.\(id.uuidString).state"
  }

  static func historyCopied(_ id: UUID) -> String {
    "miniwhisper.history.copied.\(id.uuidString)"
  }
}
