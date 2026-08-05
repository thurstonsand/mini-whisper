import AppKit
import SwiftUI

// MARK: - SettingsWindowController

@MainActor final class SettingsWindowController: NSObject, NSWindowDelegate {
  // MARK: Internal

  func present() {
    if let window {
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
      window.makeFirstResponder(nil)
      return
    }

    let window = NSWindow(
      contentRect: .zero,
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false,
    )
    window.title = Channel.name
    window.toolbarStyle = .unified
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.moveToActiveSpace]
    window.minSize = NSSize(width: 680, height: 480)
    window.setAccessibilityIdentifier(AccessibilityID.settingsWindow)
    window.setAccessibilityLabel("\(Channel.name) Settings")
    window.setAccessibilityTitle("\(Channel.name) Settings")
    window.contentView = NSHostingView(rootView: SettingsWindowView())
    window.setContentSize(NSSize(width: 860, height: 620))
    window.center()
    window.delegate = self
    self.window = window

    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(nil)
  }

  func windowWillClose(_ notification: Notification) {
    guard notification.object as? NSWindow === window else {
      return
    }
    window = nil
  }

  // MARK: Private

  private var window: NSWindow?
}

// MARK: - SettingsDestination

enum SettingsDestination: String, CaseIterable, Identifiable {
  case settings = "Settings"
  case history = "History"
  case model = "Model"
  case dictionary = "Dictionary"
  case cleanup = "Cleanup"

  // MARK: Internal

  var id: Self {
    self
  }

  var symbolName: String {
    switch self {
    case .settings:
      "gearshape"
    case .history:
      "clock.arrow.circlepath"
    case .model:
      "waveform"
    case .dictionary:
      "character.book.closed"
    case .cleanup:
      "wand.and.sparkles"
    }
  }

  var accessibilityIdentifier: String {
    switch self {
    case .settings:
      AccessibilityID.settingsSidebarSettings
    case .history:
      AccessibilityID.settingsSidebarHistory
    case .model:
      AccessibilityID.settingsSidebarModel
    case .dictionary:
      AccessibilityID.settingsSidebarDictionary
    case .cleanup:
      AccessibilityID.settingsSidebarCleanup
    }
  }

  var placeholderCaption: String {
    switch self {
    case .settings:
      "Dictation controls will appear here."
    case .history:
      "Your dictation history will appear here."
    case .model:
      "Speech model controls will appear here."
    case .dictionary:
      "Custom words and corrections will appear here."
    case .cleanup:
      "Transcript cleanup controls will appear here."
    }
  }
}

// MARK: - SettingsWindowView

struct SettingsWindowView: View {
  // MARK: Internal

  var body: some View {
    NavigationSplitView {
      List(selection: $selection) {
        destinationRow(.settings)
        Section {
          ForEach(SettingsDestination.allCases.dropFirst()) { destination in
            destinationRow(destination)
          }
        }
      }
      .navigationSplitViewColumnWidth(min: 160, ideal: 176, max: 220)
      .scrollBounceBehavior(.basedOnSize)
      .toolbar(removing: .sidebarToggle)
      .accessibilityIdentifier(AccessibilityID.settingsSidebar)
      .accessibilityLabel("Settings sections")
    } detail: {
      SettingsPlaceholderPane(destination: selection)
        .navigationTitle(selection.rawValue)
    }
  }

  // MARK: Private

  @State private var selection = SettingsDestination.settings

  private func destinationRow(_ destination: SettingsDestination) -> some View {
    Label {
      Text(destination.rawValue)
        .accessibilityIdentifier(destination.accessibilityIdentifier)
        .accessibilityLabel("\(destination.rawValue) section")
        .accessibilityValue(destination.rawValue)
    } icon: {
      Image(systemName: destination.symbolName)
    }
    .tag(destination)
  }
}

// MARK: - SettingsPlaceholderPane

private struct SettingsPlaceholderPane: View {
  let destination: SettingsDestination

  var body: some View {
    VStack(spacing: 8) {
      Text(destination.rawValue)
        .font(.title2)
      Text(destination.placeholderCaption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityIdentifier(AccessibilityID.settingsPlaceholder)
    .accessibilityLabel("\(destination.rawValue). \(destination.placeholderCaption)")
  }
}
