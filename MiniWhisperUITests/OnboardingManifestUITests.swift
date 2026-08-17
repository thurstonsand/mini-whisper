import AppKit
import XCTest

// MARK: - OnboardingManifestUITests

final class OnboardingManifestUITests: MiniWhisperUITestCase, SurfaceTagged {
  // MARK: Internal

  static let surfaces: Set<Surface> = [.onboarding]

  @MainActor func testOnboardingAccessibilityManifest() throws {
    let app = launch("onboarding-welcome")
    defer { terminate(app) }
    try assertManifest(
      in: app,
      audits: true,
      elements: [
        contract(.window, "miniwhisper.onboarding.window", "Set Up \(appName)"),
        contract(.group, "miniwhisper.onboarding.welcome", "Welcome to \(appName)"),
        contract(
          .staticText, "miniwhisper.onboarding.welcome.title", "Application name", appName,
        ),
        contract(
          .staticText, "miniwhisper.onboarding.welcome.summary", "Welcome summary",
          "Fast, accurate dictation that runs on your Mac.",
        ),
        contract(
          .staticText, "miniwhisper.onboarding.welcome.model-info", "Model download information",
          "Download the speech model in the background while you finish setup.",
        ),
        contract(
          .button, "miniwhisper.onboarding.download-model", "Download Parakeet v2", isEnabled: true,
          isActionable: true,
        ),
      ],
    )

    for permission in PermissionManifest.allCases {
      presentScene(permission.scene)
      try assertManifest(
        in: app,
        elements: onboardingRail(permission.railValues) + permissionElements(permission),
      )
    }

    presentScene("onboarding-shortcut")
    try assertManifest(
      in: app,
      elements: onboardingRail(
        ["Complete", "Current", "Available; Downloading Parakeet v2 42%", "Available"],
      ) + [
        contract(.group, "miniwhisper.onboarding.shortcut", "Activation shortcut setup"),
        contract(
          .staticText, "miniwhisper.onboarding.shortcut.title", "Shortcut heading",
          "Activating \(appName)",
        ),
        contract(
          .staticText, "miniwhisper.onboarding.shortcut.summary", "Shortcut information",
          "Shortcut to start dictation.",
        ),
        contract(
          .button, "miniwhisper.onboarding.shortcut.binding", "Dictation shortcut", "⌥ Opt →",
          isEnabled: true, isActionable: true,
        ),
        contract(
          .staticText, "miniwhisper.onboarding.shortcut.binding.state",
          "Dictation shortcut ring", "Ring off",
        ),
        contract(
          .staticText, "miniwhisper.onboarding.shortcut.caption", "Shortcut guidance",
          "Click the shortcut to change",
        ),
        contract(
          .button, "miniwhisper.onboarding.shortcut.continue", "Continue", isEnabled: true,
          isActionable: true,
        ),
      ],
    )

    presentScene("onboarding-model")
    try assertManifest(
      in: app,
      elements: onboardingRail([
        "Complete",
        "Complete",
        "Current; Downloading Parakeet v2 42%",
        "Available",
      ]) +
        [
          contract(.group, "miniwhisper.onboarding.model", "Speech model setup"),
          contract(
            .staticText, "miniwhisper.onboarding.model.title", "Model setup heading",
            "Prepare Parakeet v2",
          ),
          contract(
            .staticText, "miniwhisper.onboarding.model.summary", "Model setup information",
            "Downloads once (~550 MB), then everything runs on this Mac.",
          ),
          contract(
            .staticText, "miniwhisper.onboarding.model.status", "Model status",
            "Downloading Parakeet v2…",
          ),
          contract(
            .progressIndicator, "miniwhisper.onboarding.model-progress", "Model download", "0.42",
          ),
        ],
    )

    presentScene("onboarding-try-it")
    try assertManifest(
      in: app,
      elements: onboardingRail(["Complete", "Complete", "Complete", "Current"]) + [
        contract(.group, "miniwhisper.onboarding.try-it", "Try \(appName)"),
        contract(
          .staticText, "miniwhisper.onboarding.try-it.title", "Try it heading", "Give it a try",
        ),
        contract(
          .staticText, "miniwhisper.onboarding.try-it.instructions", "Try it instructions",
          "Focus the text box below, hold ⌥ Opt →, and read the line aloud. Release when you're done, or double-tap ⌥ Opt → to keep recording until you tap it again.",
        ), contract(.textField, "miniwhisper.onboarding.try-it.text", "Try dictation", ""),
        contract(
          .staticText, "miniwhisper.onboarding.try-it.hotkey", "Dictation hotkey", "⌥ Opt →",
        ),
        contract(
          .staticText, "miniwhisper.onboarding.try-it.guidance", "Try it guidance",
          "Speak to complete…",
        ),
        contract(
          .button, "miniwhisper.onboarding.try-it.skip", "Skip test dictation", isEnabled: true,
          isActionable: true,
        ),
        contract(
          .staticText, "miniwhisper.onboarding.try-it.skip.state", "Skip ring", "Ring off",
        ),
      ],
    )

    presentScene("onboarding-ready")
    try assertManifest(
      in: app,
      elements: onboardingRail(["Complete", "Complete", "Complete", "Complete"]) + [
        contract(.group, "miniwhisper.onboarding.ready", "\(appName) is ready"),
        contract(.staticText, "miniwhisper.onboarding.ready.title", "Setup status", "Ready"),
        contract(
          .staticText, "miniwhisper.onboarding.ready.summary", "Ready instructions",
          "Your first dictation made the full trip. Hold ⌥ Opt → in any text field and speak.",
        ),
        contract(
          .staticText, "miniwhisper.onboarding.ready.transcript", "Completed dictation",
          "MiniWhisper is ready.",
        ),
        contract(
          .button, "miniwhisper.onboarding.ready.finish", "Start Dictating", isEnabled: true,
          isActionable: true,
        ),
      ],
    )
  }

  // MARK: Private

  private func onboardingRail(_ values: [String]) -> [AccessibilityContract] {
    [
      contract(.window, "miniwhisper.onboarding.window", "Set Up \(appName)"),
      contract(.group, "miniwhisper.onboarding.rail", "Setup steps"),
      contract(.staticText, "miniwhisper.onboarding.rail.brand", "Application name", appName),
      contract(
        .staticText, "miniwhisper.onboarding.rail.tagline", "Application description",
        "fast and accurate dictation",
      ),
      contract(
        .button, "miniwhisper.onboarding.rail.permissions", "Permissions", values[0],
        isEnabled: true, isActionable: true,
      ),
      contract(
        .button, "miniwhisper.onboarding.rail.shortcut", "Shortcut", values[1], isEnabled: true,
        isActionable: true,
      ),
      contract(
        .button, "miniwhisper.onboarding.rail.model", "Speech Model", values[2], isEnabled: true,
        isActionable: true,
      ),
      contract(
        .button, "miniwhisper.onboarding.rail.try-it", "Try It", values[3], isEnabled: true,
        isActionable: true,
      ),
    ]
  }

  private func permissionElements(_ manifest: PermissionManifest) -> [AccessibilityContract] {
    let action = manifest.action
    let statuses = manifest.statuses
    var elements = [
      contract(.group, "miniwhisper.onboarding.permissions", "Permissions setup"),
      contract(
        .staticText, "miniwhisper.onboarding.permissions.title", "Permissions heading",
        "We need access to a few things first",
      ),
      contract(
        .staticText, "miniwhisper.onboarding.permissions.summary", "Permissions information",
        "macOS prompts for both. Grant them in the order they appear.",
      ),
      contract(
        .staticText, "miniwhisper.onboarding.permission.microphone", "Microphone",
        "Hear your beautiful voice",
      ),
      contract(
        .staticText, "miniwhisper.onboarding.permission.microphone.status", "Microphone status",
        statuses[0],
      ),
      contract(
        .staticText, "miniwhisper.onboarding.permission.accessibility", "Accessibility",
        "Listen for the hotkey and paste at your cursor.",
      ),
      contract(
        .staticText, "miniwhisper.onboarding.permission.accessibility.status",
        "Accessibility status", statuses[1],
      ),
      contract(
        .staticText, "miniwhisper.onboarding.permissions.guidance", "Permissions guidance",
        manifest.guidance,
      ),
    ]
    elements.append(
      contract(.button, action.identifier, action.label, isEnabled: true, isActionable: true),
    )
    return elements
  }
}

// MARK: - PermissionAction

private enum PermissionAction {
  case microphone
  case accessibility

  // MARK: Internal

  var identifier: String {
    switch self {
    case .microphone:
      "miniwhisper.onboarding.permission.microphone.action"
    case .accessibility:
      "miniwhisper.onboarding.permission.accessibility.action"
    }
  }

  var label: String {
    switch self {
    case .microphone:
      "Grant Microphone"
    case .accessibility:
      "Grant Accessibility"
    }
  }
}

// MARK: - PermissionManifest

private enum PermissionManifest: CaseIterable {
  case microphone
  case accessibility

  // MARK: Internal

  var scene: String {
    switch self {
    case .microphone:
      "onboarding-permissions-microphone"
    case .accessibility:
      "onboarding-permissions-accessibility"
    }
  }

  var action: PermissionAction {
    switch self {
    case .microphone:
      .microphone
    case .accessibility:
      .accessibility
    }
  }

  var statuses: [String] {
    switch self {
    case .microphone:
      ["Required", "Required"]
    case .accessibility:
      ["Granted", "Required"]
    }
  }

  var guidance: String {
    "Continue after granting both"
  }

  var railValues: [String] {
    ["Current", "Available", "Available; Downloading Parakeet v2 42%", "Available"]
  }
}
