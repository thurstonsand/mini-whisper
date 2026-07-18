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

    let dictationItem = NSMenuItem()
    let dictationView = NSHostingView(
      rootView: DictationRowView(
        isMicGranted: state.isMicGranted,
        onDictation: { [weak self] in self?.store.send(.menuBar(.dictationTapped)) },
        onRequestMicAccess: { [weak self] in self?.store.send(.menuBar(.requestMicAccessTapped)) }))
    dictationView.frame.size = dictationView.fittingSize
    dictationItem.view = dictationView
    menu.addItem(dictationItem)

    let settingsItem = NSMenuItem(title: "Settings...", action: nil, keyEquivalent: ",")
    menu.addItem(settingsItem)

    menu.addItem(.separator())

    let quitItem = NSMenuItem(
      title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    menu.addItem(quitItem)

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

struct DictationRowView: View {
  var isMicGranted: Bool
  var onDictation: () -> Void
  var onRequestMicAccess: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Text("Start Dictation").opacity(isMicGranted ? 1 : 0.4)

      Spacer()

      if isMicGranted {
        Text("⌘D").foregroundStyle(.secondary)
      } else {
        Button(action: onRequestMicAccess) {
          Image(systemName: "mic").foregroundStyle(.white).padding(4).background(
            Color.orange, in: RoundedRectangle(cornerRadius: 4))
        }.buttonStyle(.plain)
      }
    }.padding(.horizontal, 14).padding(.vertical, 6).frame(minWidth: 180).contentShape(Rectangle())
      .onTapGesture(perform: onDictation)
  }
}
