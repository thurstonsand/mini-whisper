import AppKit
import SwiftUI

// MARK: - SettingsPopUpButton

/// The settings window's one bridge to `NSPopUpButton`. SwiftUI's `Picker` cannot be opened from
/// the keyboard
/// or dim an individual row, and both are settings-window grammar, so every pop-up here is this.
struct SettingsPopUpButton<Value: Equatable>: NSViewRepresentable {
  struct Option: Equatable {
    // MARK: Lifecycle

    init(value: Value, title: String, isSecondary: Bool = false) {
      self.value = value
      self.title = title
      self.isSecondary = isSecondary
    }

    // MARK: Internal

    let value: Value
    let title: String
    let isSecondary: Bool
  }

  @MainActor final class Coordinator: NSObject {
    // MARK: Lifecycle

    init(activation: Int, onSelection: @escaping (Value) -> Void) {
      self.activation = activation
      self.onSelection = onSelection
    }

    // MARK: Internal

    var options: [Option] = []
    var activation: Int
    var onSelection: (Value) -> Void

    @objc func selectionChanged(_ sender: NSPopUpButton) {
      guard options.indices.contains(sender.indexOfSelectedItem) else {
        return
      }
      onSelection(options[sender.indexOfSelectedItem].value)
    }
  }

  let options: [Option]
  let selection: Value
  let activation: Int
  let onSelection: (Value) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(activation: activation, onSelection: onSelection)
  }

  func makeNSView(context: Context) -> NSPopUpButton {
    let button = NSPopUpButton(frame: .zero, pullsDown: false)
    button.target = context.coordinator
    button.action = #selector(Coordinator.selectionChanged(_:))
    return button
  }

  func updateNSView(_ button: NSPopUpButton, context: Context) {
    context.coordinator.options = options
    context.coordinator.onSelection = onSelection
    if button.itemTitles != options.map(\.title) {
      button.removeAllItems()
      for option in options {
        button.addItem(withTitle: option.title)
      }
    }
    if let selectedIndex = options.firstIndex(where: { $0.value == selection }) {
      button.selectItem(at: selectedIndex)
    }
    // A secondary choice dims only while it is the selection, so the collapsed control reads
    // quiet without the open menu ever showing a greyed row that looks disabled.
    for (index, option) in options.enumerated() where option.isSecondary {
      guard let item = button.item(at: index) else {
        continue
      }
      let wanted: NSAttributedString? =
        index == button.indexOfSelectedItem
          ? NSAttributedString(
            string: option.title, attributes: [.foregroundColor: NSColor.secondaryLabelColor],
          ) : nil
      if item.attributedTitle != wanted {
        item.attributedTitle = wanted
      }
    }
    // Only a click opens a pop-up button, so Return on this row arrives as a changed count.
    guard activation != context.coordinator.activation else {
      return
    }
    context.coordinator.activation = activation
    DispatchQueue.main.async { button.performClick(nil) }
  }
}
