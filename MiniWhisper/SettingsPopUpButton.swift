import AppKit
import SwiftUI

// MARK: - SettingsPopUpButton

/// The settings window's one bridge to `NSPopUpButton`. SwiftUI's `Picker` cannot be opened from
/// the keyboard
/// or dim an individual row, and both are settings-window grammar, so every pop-up here is this.
struct SettingsPopUpButton<Value: Equatable>: NSViewRepresentable {
  struct Option: Equatable {
    // MARK: Lifecycle

    init(
      value: Value, title: String, isSecondary: Bool = false, symbol: String? = nil,
      status: Status? = nil,
    ) {
      self.value = value
      self.title = title
      self.isSecondary = isSecondary
      self.symbol = symbol
      self.status = status
    }

    // MARK: Internal

    /// Status supplies a warning symbol and menu accessibility help, never part of the title.
    struct Status: Equatable {
      let text: String
      let isProblem: Bool
    }

    let value: Value
    let title: String
    let isSecondary: Bool
    let symbol: String?
    let status: Status?
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

  final class Control: NSPopUpButton {
    var isRinged = false

    override func draw(_ dirtyRect: NSRect) {
      super.draw(dirtyRect)
      guard isRinged, let cell else {
        return
      }
      // Menu width stays stable; only the selected title and arrow wear the focus ring.
      let title = cell.titleRect(forBounds: bounds)
      let ring = NSRect(x: title.minX - 4, y: 1,
                        width: bounds.maxX - title.minX + 3, height: bounds.height - 2)
      NSGraphicsContext.saveGraphicsState()
      NSFocusRingPlacement.only.set()
      NSBezierPath(roundedRect: ring, xRadius: 5, yRadius: 5).fill()
      NSGraphicsContext.restoreGraphicsState()
    }
  }

  let options: [Option]
  let selection: Value
  let activation: Int
  let isRinged: Bool
  let onSelection: (Value) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(activation: activation, onSelection: onSelection)
  }

  func makeNSView(context: Context) -> Control {
    let button = Control(frame: .zero, pullsDown: false)
    // The control is as wide as its widest option, which a long model id can make very wide. A
    // settings row reads right to left from its value, so the collapsed title stays against the
    // chevron instead of stranded at the far end of the button.
    button.alignment = .right
    button.focusRingType = .none
    button.target = context.coordinator
    button.action = #selector(Coordinator.selectionChanged(_:))
    return button
  }

  func updateNSView(_ button: Control, context: Context) {
    button.isRinged = isRinged
    button.needsDisplay = true
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
    for (index, option) in options.enumerated() where option.symbol != nil || option.status != nil {
      guard let item = button.item(at: index) else {
        continue
      }
      let font = button.font ?? .systemFont(ofSize: NSFont.systemFontSize)
      let title = NSMutableAttributedString()
      // Inline rather than the item's image: the cell pins an image to the far edge, away from a
      // right-aligned title.
      let isProblem = option.status?.isProblem == true
      if let symbol = isProblem ? "exclamationmark.triangle.fill" : option.symbol,
         let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
         .withSymbolConfiguration(
           NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)
             .applying(.init(paletteColors: [isProblem ? .systemOrange : .labelColor])),
         )
      {
        let attachment = NSTextAttachment()
        attachment.image = image
        title.append(NSAttributedString(attachment: attachment))
        title.append(NSAttributedString(string: " ", attributes: [.font: font]))
      }
      title.append(NSAttributedString(string: option.title, attributes: [.font: font]))
      item.setAccessibilityHelp(option.status?.text)
      if item.attributedTitle != title {
        item.attributedTitle = title
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
