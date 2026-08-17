import AppKit
import ComposableArchitecture

@MainActor final class MenuBarController: NSObject, NSMenuDelegate {
  // MARK: Lifecycle

  init(store: StoreOf<AppFeature>, refreshesStateOnOpen: Bool = true) {
    self.store = store
    self.refreshesStateOnOpen = refreshesStateOnOpen
    settingsWindowController = SettingsWindowController(
      store: store.scope(state: \.settingsWindow, action: \.settingsWindow),
    )
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    super.init()

    statusItem.button?.setAccessibilityIdentifier(AccessibilityID.menuStatusItem)
    statusItem.button?.setAccessibilityLabel(Channel.name)
    statusItem.button?.setAccessibilityHelp("Open the \(Channel.name) menu")
    menu.autoenablesItems = false
    menu.appearance = NSApp.appearance
    menu.minimumWidth = DictionaryQuickAddView.width
    menu.delegate = self
    statusItem.menu = menu
    observeIcon()
    renderIcon(store.state.health.isDegraded)
  }

  // MARK: Internal

  func menuNeedsUpdate(_ menu: NSMenu) {
    if refreshesStateOnOpen {
      store.send(.menuWillOpen)
    }
    quickAddView.improvesRecognition = store.state.settingsWindow.dictionary.improveRecognition
    rebuild(menu, state: store.state.menuBar)
  }

  func menuDidClose(_: NSMenu) {
    quickAddView.collapse()
  }

  func presentAbout() {
    aboutWindowController.present()
  }

  func presentSettings(
    destination: SettingsDestination = .settings, initialFocus: SettingsWindowFocus? = nil,
  ) {
    settingsWindowController.present(destination: destination, initialFocus: initialFocus)
  }

  // MARK: Private

  /// Tinted rather than templated: the orange is the warning, so the menu must not recolour it.
  private static let warningImage: NSImage? = {
    let image = NSImage(
      systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Warning",
    )?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemOrange]))
    image?.isTemplate = false
    return image
  }()

  private let store: StoreOf<AppFeature>
  private let statusItem: NSStatusItem
  private let refreshesStateOnOpen: Bool
  private let menu = NSMenu()
  private let aboutWindowController = AboutWindowController()
  private let settingsWindowController: SettingsWindowController
  private var renderedIconSymbolName: String?
  private lazy var quickAddView = makeQuickAddView()
  private lazy var quickAddItem: NSMenuItem = {
    let item = NSMenuItem(title: "Add to Dictionary…", action: nil, keyEquivalent: "")
    item.view = quickAddView
    item.setAccessibilityIdentifier(AccessibilityID.menuQuickAdd)
    item.setAccessibilityLabel("Add to Dictionary…")
    return item
  }()

  /// Only whether the app is broken is watched, and `renderIcon` drops a repeat of the symbol it
  /// already drew — a download's progress does retrigger this, but it cannot repaint anything.
  /// Reading the menu's wording here would instead rebuild every string in a closed menu.
  private func observeIcon() {
    withObservationTracking {
      _ = self.store.state.health.isDegraded
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else {
          return
        }
        observeIcon()
        renderIcon(store.state.health.isDegraded)
      }
    }
  }

  private func renderIcon(_ isDegraded: Bool) {
    let symbolName = isDegraded ? "mic.slash" : "mic"
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

    for degradation in state.degradations {
      let presentation = degradation.presentation
      let repair = item(
        title: presentation.title, identifier: AccessibilityID.menuRepair(degradation),
        label: presentation.title, value: presentation.reason,
        action: #selector(repairDegradation),
      )
      repair.representedObject = degradation
      repair.image = MenuBarController.warningImage
      menu.addItem(repair)
    }

    menu.addItem(.separator())
    menu.addItem(
      item(
        title: "Copy Last Transcript", identifier: AccessibilityID.menuCopyLastTranscript,
        label: "Copy Last Transcript", action: #selector(copyLastTranscript),
        isEnabled: state.canCopyLastTranscript,
      ),
    )

    menu.addItem(quickAddItem)

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

  private func makeQuickAddView() -> DictionaryQuickAddView {
    let view = DictionaryQuickAddView(frame: .zero)
    view.refuses = { [store] in
      store.state.settingsWindow.dictionary.refusalReason
    }
    view.submit = { [store] word, misspelling in
      store.send(
        .settingsWindow(.dictionary(.quickAddSubmitted(word: word, misspelling: misspelling))),
      )
    }
    return view
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

  @objc private func repairDegradation(_ sender: NSMenuItem) {
    guard let degradation = sender.representedObject as? Degradation else {
      preconditionFailure("A repair row was built without the failure it repairs")
    }
    store.send(.repairRequested(degradation))
  }

  @objc private func copyLastTranscript() {
    store.send(.copyLastTranscript)
  }

  @objc private func showSettings() {
    presentSettings()
  }

  @objc private func showAbout() {
    presentAbout()
  }
}
