import Foundation

/// The running channel — MiniWhisper, MiniWhisper Nightly, or MiniWhisper Dev. The bundle is the
/// single source of truth for which one this is, exactly as it is for the TCC grants, so the name
/// the user reads in the menu and in System Settings is the name that owns the files below it.
enum Channel {
  static let name: String = {
    guard let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String else {
      fatalError("CFBundleName is missing; the running channel cannot be named")
    }
    return name
  }()

  static let supportDirectory = FileManager.default.urls(
    for: .applicationSupportDirectory, in: .userDomainMask,
  )[0].appending(path: name, directoryHint: .isDirectory)

  static let settingsFile = supportDirectory.appending(path: "settings.json")
  static let historyDirectory = supportDirectory.appending(
    path: "History", directoryHint: .isDirectory,
  )
  static let historyFile = historyDirectory.appending(path: "history.json")
  static let historyAudioDirectory = historyDirectory.appending(
    path: "audio", directoryHint: .isDirectory,
  )
  static let engineRoot = supportDirectory.appending(
    path: "Engine/pinned-v1", directoryHint: .isDirectory,
  )
  static let onboardingMarker = supportDirectory.appending(path: "onboarding-completed")
  static let modelDownloadConsentMarker = supportDirectory.appending(
    path: "model-download-consented",
  )
}
