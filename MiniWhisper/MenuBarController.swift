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
    menu.addItem(
      NSMenuItem(
        title: "Quit MiniWhisper", action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"))

    return menu
  }
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
