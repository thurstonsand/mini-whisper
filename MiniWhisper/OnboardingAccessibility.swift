import AppSettings
import ASREngine

/// Onboarding's accessibility contract is a lookup table, not a view: which identifier a step or a
/// permission answers to, and what its value reads as. Kept whole and apart so the pages stay
/// layout and the contract stays reviewable in one place.
enum OnboardingAccessibility {
  static func railIdentifier(_ step: OnboardingStep) -> String {
    switch step {
    case .keys:
      AccessibilityID.onboardingRailKeys
    case .permissions:
      AccessibilityID.onboardingRailPermissions
    case .shortcut:
      AccessibilityID.onboardingRailShortcut
    case .model:
      AccessibilityID.onboardingRailModel
    case .tryIt,
         .ready:
      AccessibilityID.onboardingRailTryIt
    }
  }

  static func railValue(
    step: OnboardingStep, engine: SpeechEngine, readiness: EngineReadiness, isComplete: Bool,
    isCurrent: Bool, problem: String?, downloadProgress: Double? = nil,
  ) -> String {
    if let problem {
      return "\(isCurrent ? "Current" : "Incomplete"); \(problem)"
    }
    if isComplete {
      return "Complete"
    }
    let position = isCurrent ? "Current" : "Available"
    guard step == .model else {
      return position
    }
    if let downloadProgress {
      return "\(position); Downloading models \(DownloadProgress.percentage(downloadProgress))"
    }
    switch readiness {
    case let .downloading(fraction):
      return "\(position); Downloading \(engine.name) \(DownloadProgress.percentage(fraction))"
    case .compiling:
      return "\(position); Compiling"
    case .prewarming:
      return "\(position); Prewarming"
    case .modelMissing:
      return position
    case .ready:
      return position
    case .failed:
      return "\(position); Setup failed"
    case .credentialMissing:
      return "\(position); Needs a key"
    }
  }

  static func permissionIdentifier(_ permission: OnboardingPermission) -> String {
    switch permission {
    case .microphone:
      AccessibilityID.onboardingPermissionMicrophone
    case .accessibility:
      AccessibilityID.onboardingPermissionAccessibility
    }
  }

  static func permissionStatusIdentifier(_ permission: OnboardingPermission) -> String {
    switch permission {
    case .microphone:
      AccessibilityID.onboardingPermissionMicrophoneStatus
    case .accessibility:
      AccessibilityID.onboardingPermissionAccessibilityStatus
    }
  }

  static func permissionActionIdentifier(_ permission: OnboardingPermission) -> String {
    switch permission {
    case .microphone:
      AccessibilityID.onboardingPermissionMicrophoneAction
    case .accessibility:
      AccessibilityID.onboardingPermissionAccessibilityAction
    }
  }

  static func permissionStatus(
    isGranted: Bool, isRequesting: Bool, showsSettings: Bool,
  ) -> String {
    if isGranted {
      return "Granted"
    }
    if isRequesting {
      return "Waiting"
    }
    if showsSettings {
      return "Needs settings"
    }
    return "Required"
  }
}
