import AppKit
import ComposableArchitecture

@MainActor final class MenuBarController: NSObject, NSMenuDelegate {
  private let store: StoreOf<AppFeature>
  private let statusItem: NSStatusItem
  private let menu = NSMenu()
  private var renderedIconSymbolName: String?

  init(store: StoreOf<AppFeature>) {
    self.store = store
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    super.init()

    statusItem.button?.setAccessibilityIdentifier("MiniWhisperStatusItem")
    menu.autoenablesItems = false
    menu.delegate = self
    statusItem.menu = menu
    observeIcon()
    renderIcon(store.state.menuBar.iconSymbolName)
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    store.send(.menuWillOpen)
    rebuild(menu, state: store.state.menuBar)
  }

  private func observeIcon() {
    withObservationTracking {
      _ = self.store.state.menuBar.iconSymbolName
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.observeIcon()
        self.renderIcon(self.store.state.menuBar.iconSymbolName)
      }
    }
  }

  private func renderIcon(_ symbolName: String) {
    guard symbolName != renderedIconSymbolName else { return }
    renderedIconSymbolName = symbolName
    let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "MiniWhisper")
    image?.isTemplate = true
    statusItem.button?.image = image
  }

  private func rebuild(_ menu: NSMenu, state: MenuBarViewState) {
    menu.removeAllItems()

    let statusLine = NSMenuItem(title: state.statusText, action: nil, keyEquivalent: "")
    statusLine.isEnabled = false
    menu.addItem(statusLine)

    if let repairTitle = state.repairTitle {
      menu.addItem(.separator())
      menu.addItem(item(title: repairTitle, action: #selector(repairDegradedState)))
    }

    menu.addItem(.separator())
    let copyItem = item(title: "Copy Last Transcript", action: #selector(copyLastTranscript))
    copyItem.isEnabled = state.canCopyLastTranscript
    menu.addItem(copyItem)

    let soundsItem = item(title: "Sounds", action: #selector(toggleSounds))
    soundsItem.state = state.soundsEnabled ? .on : .off
    menu.addItem(soundsItem)

    let launchItem = item(title: "Launch at Login", action: #selector(toggleLaunchAtLogin))
    launchItem.state = state.launchAtLoginRegistered ? .on : .off
    menu.addItem(launchItem)

    menu.addItem(item(title: "Settings File…", action: #selector(openSettingsFile)))

    menu.addItem(.separator())
    menu.addItem(item(title: "About MiniWhisper", action: #selector(showAbout)))

    let quitItem = NSMenuItem(
      title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    quitItem.isEnabled = true
    menu.addItem(quitItem)
  }

  private func item(title: String, action: Selector) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    item.isEnabled = true
    return item
  }

  @objc private func repairDegradedState() { store.send(.repairDegradedState) }

  @objc private func copyLastTranscript() { store.send(.copyLastTranscript) }

  @objc private func toggleSounds() { store.send(.toggleSounds) }

  @objc private func toggleLaunchAtLogin() { store.send(.toggleLaunchAtLogin) }

  @objc private func openSettingsFile() { store.send(.openSettingsFile) }

  @objc private func showAbout() {
    let credits = NSAttributedString(
      string: """
        Speech recognition uses NVIDIA Parakeet TDT 0.6B v2, licensed under CC BY 4.0.
        https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2

        MiniWhisper uses FluidAudio, licensed under the Apache License 2.0.
        https://github.com/FluidInference/FluidAudio
        """)
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
  }
}
