import ComposableArchitecture
import SwiftUI

@MainActor final class MenuBarController {
  private var statusItem: NSStatusItem?
  private let store: StoreOf<AppFeature>
  private var lastRenderedState: MenuBarViewState?

  init(store: StoreOf<AppFeature>) {
    self.store = store
    setupStatusItem()
    observeStore()
    render(store.state.menuBar)
  }

  private func setupStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem?.button?.setAccessibilityIdentifier("MiniWhisperStatusItem")
  }

  private func observeStore() {
    withObservationTracking {
      _ = self.store.state.menuBar
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.observeStore()
        self.render(self.store.state.menuBar)
      }
    }
  }

  private func render(_ state: MenuBarViewState) {
    guard state != lastRenderedState else { return }
    lastRenderedState = state
    statusItem?.button?.image = NSImage(
      systemSymbolName: state.iconSymbolName, accessibilityDescription: "MiniWhisper")
    statusItem?.button?.image?.isTemplate = true
    statusItem?.menu = buildMenu(state)
  }

  private func buildMenu(_ state: MenuBarViewState) -> NSMenu {
    let menu = NSMenu()

    let headerItem = NSMenuItem()
    let headerView = NSHostingView(rootView: MenuHeaderView(statusText: state.statusText))
    headerView.frame.size = headerView.fittingSize
    headerItem.view = headerView
    menu.addItem(headerItem)

    menu.addItem(.separator())
    menu.addItem(buildPillDemoItem())
    menu.addItem(.separator())
    menu.addItem(
      NSMenuItem(
        title: "Quit MiniWhisper", action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"))

    return menu
  }

  private func buildPillDemoItem() -> NSMenuItem {
    let item = NSMenuItem(title: "Pill Demos", action: nil, keyEquivalent: "")
    let submenu = NSMenu()
    submenu.addItem(demoItem(title: "Transcribing", action: #selector(showTranscribingDemo)))
    submenu.addItem(demoItem(title: "No Speech Detected", action: #selector(showNoSpeechDemo)))
    submenu.addItem(demoItem(title: "Copied to Clipboard", action: #selector(showCopiedDemo)))
    submenu.addItem(.separator())
    submenu.addItem(demoItem(title: "Hide Pill", action: #selector(hidePillDemo)))
    item.submenu = submenu
    return item
  }

  private func demoItem(title: String, action: Selector) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    return item
  }

  @objc private func showTranscribingDemo() { store.send(.pill(.transcribingStarted)) }

  @objc private func showNoSpeechDemo() { store.send(.pill(.noSpeechDetected)) }

  @objc private func showCopiedDemo() { store.send(.pill(.copiedToClipboard)) }

  @objc private func hidePillDemo() { store.send(.pill(.dismiss)) }
}

struct MenuHeaderView: View {
  var statusText: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("MiniWhisper").font(.headline)
      Text(statusText).font(.subheadline).foregroundStyle(.secondary)
    }.padding(.horizontal, 14).padding(.vertical, 8)
  }
}
