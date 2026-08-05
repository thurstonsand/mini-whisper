import AppKit
import ComposableArchitecture

@MainActor final class MenuBarController: NSObject, NSMenuDelegate {
  // MARK: Lifecycle

  init(store: StoreOf<AppFeature>, refreshesStateOnOpen: Bool = true) {
    self.store = store
    self.refreshesStateOnOpen = refreshesStateOnOpen
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    super.init()

    statusItem.button?.setAccessibilityIdentifier(AccessibilityID.menuStatusItem)
    statusItem.button?.setAccessibilityLabel(Channel.name)
    statusItem.button?.setAccessibilityHelp("Open the \(Channel.name) menu")
    menu.autoenablesItems = false
    menu.delegate = self
    statusItem.menu = menu
    observeIcon()
    renderIcon(store.state.menuBar.iconSymbolName)
  }

  // MARK: Internal

  func menuNeedsUpdate(_ menu: NSMenu) {
    if refreshesStateOnOpen {
      store.send(.menuWillOpen)
    }
    rebuild(menu, state: store.state.menuBar)
  }

  func refreshAgentScene() {
    rebuild(menu, state: store.state.menuBar)
  }

  func presentAbout() {
    aboutWindowController.present()
  }

  func presentSettings() {
    settingsWindowController.present()
  }

  // MARK: Private

  private let store: StoreOf<AppFeature>
  private let statusItem: NSStatusItem
  private let refreshesStateOnOpen: Bool
  private let menu = NSMenu()
  private let aboutWindowController = AboutWindowController()
  private let settingsWindowController = SettingsWindowController()
  private var renderedIconSymbolName: String?

  private func observeIcon() {
    withObservationTracking {
      _ = self.store.state.menuBar.iconSymbolName
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else {
          return
        }
        observeIcon()
        renderIcon(store.state.menuBar.iconSymbolName)
      }
    }
  }

  private func renderIcon(_ symbolName: String) {
    guard symbolName != renderedIconSymbolName else {
      return
    }
    renderedIconSymbolName = symbolName
    let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: Channel.name)
    image?.isTemplate = true
    statusItem.button?.image = image
  }

  private func rebuild(_ menu: NSMenu, state: MenuBarViewState) {
    menu.removeAllItems()

    menu.addItem(
      item(
        title: state.statusText, identifier: AccessibilityID.menuStatus, label: "Status",
        value: state.accessibilityStatusText, action: nil, isEnabled: false,
      ),
    )

    if let repairTitle = state.repairTitle {
      menu.addItem(.separator())
      menu.addItem(
        item(
          title: repairTitle, identifier: AccessibilityID.menuRepair, label: repairTitle,
          action: #selector(repairDegradedState),
        ),
      )
    }

    menu.addItem(.separator())
    menu.addItem(
      item(
        title: "Copy Last Transcript", identifier: AccessibilityID.menuCopyLastTranscript,
        label: "Copy Last Transcript", action: #selector(copyLastTranscript),
        isEnabled: state.canCopyLastTranscript,
      ),
    )

    let soundsValue = state.soundsEnabled ? "On" : "Off"
    let soundsItem = item(
      title: "Sounds", identifier: AccessibilityID.menuSounds, label: "Sounds", value: soundsValue,
      action: #selector(toggleSounds),
    )
    soundsItem.state = state.soundsEnabled ? .on : .off
    menu.addItem(soundsItem)

    let launchValue = state.launchAtLoginRegistered ? "On" : "Off"
    let launchItem = item(
      title: "Launch at Login", identifier: AccessibilityID.menuLaunchAtLogin,
      label: "Launch at Login", value: launchValue, action: #selector(toggleLaunchAtLogin),
    )
    launchItem.state = state.launchAtLoginRegistered ? .on : .off
    menu.addItem(launchItem)

    menu.addItem(
      item(
        title: "Settings File…", identifier: AccessibilityID.menuSettingsFile,
        label: "Open Settings File", action: #selector(openSettingsFile),
      ),
    )

    menu.addItem(.separator())
    let settingsItem = item(
      title: "Settings…", identifier: AccessibilityID.menuSettings,
      label: "Settings", action: #selector(showSettings),
    )
    settingsItem.keyEquivalent = ","
    settingsItem.keyEquivalentModifierMask = .command
    menu.addItem(settingsItem)
    menu.addItem(
      item(
        title: "About \(Channel.name)", identifier: AccessibilityID.menuAbout,
        label: "About \(Channel.name)", action: #selector(showAbout),
      ),
    )

    let quitItem = item(
      title: "Quit", identifier: AccessibilityID.menuQuit, label: "Quit \(Channel.name)",
      action: #selector(NSApplication.terminate(_:)),
    )
    quitItem.target = nil
    quitItem.keyEquivalent = "q"
    menu.addItem(quitItem)
  }

  private func item(
    title: String, identifier: String, label: String, value: String? = nil, action: Selector?,
    isEnabled: Bool = true,
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    item.isEnabled = isEnabled
    item.setAccessibilityIdentifier(identifier)
    item.setAccessibilityLabel(label)
    item.setAccessibilityValue(value)
    return item
  }

  @objc private func repairDegradedState() {
    store.send(.repairDegradedState)
  }

  @objc private func copyLastTranscript() {
    store.send(.copyLastTranscript)
  }

  @objc private func toggleSounds() {
    store.send(.toggleSounds)
  }

  @objc private func toggleLaunchAtLogin() {
    store.send(.toggleLaunchAtLogin)
  }

  @objc private func openSettingsFile() {
    store.send(.openSettingsFile)
  }

  @objc private func showSettings() {
    presentSettings()
  }

  @objc private func showAbout() {
    presentAbout()
  }
}
