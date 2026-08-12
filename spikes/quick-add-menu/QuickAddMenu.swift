import AppKit

final class QuickAddView: NSView, NSTextFieldDelegate {
  let wordField = NSTextField()
  let misspellingField = NSTextField()

  var commit: (String, String) -> Void = { _, _ in }
  var abort: () -> Void = {}

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    let heading = NSTextField(labelWithString: "Quick Add")
    heading.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)

    configure(wordField, placeholder: "Word")
    configure(misspellingField, placeholder: "Misspelling (optional)")
    wordField.nextKeyView = misspellingField
    misspellingField.nextKeyView = wordField

    let fields = NSStackView(views: [wordField, misspellingField])
    fields.orientation = .vertical
    fields.spacing = 6
    fields.distribution = .fillEqually

    let content = NSStackView(views: [heading, fields])
    content.orientation = .vertical
    content.alignment = .leading
    content.spacing = 6
    content.translatesAutoresizingMaskIntoConstraints = false
    addSubview(content)

    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
      content.topAnchor.constraint(equalTo: topAnchor, constant: 9),
      content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
      fields.widthAnchor.constraint(equalTo: content.widthAnchor),
      wordField.heightAnchor.constraint(equalToConstant: 24),
      misspellingField.heightAnchor.constraint(equalToConstant: 24),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(wordField)
    super.mouseDown(with: event)
  }

  func focusWord(reason: String) {
    let accepted = window?.makeFirstResponder(wordField) ?? false
    log("focus \(reason): accepted=\(accepted), responder=\(responderName)")
  }

  var isEditing: Bool {
    guard let editor = window?.firstResponder as? NSTextView else { return false }
    return editor.delegate as AnyObject? === wordField || editor.delegate as AnyObject? === misspellingField
  }

  func abortEditing() {
    reset()
    window?.makeFirstResponder(nil)
    abort()
  }

  func reset() {
    wordField.stringValue = ""
    misspellingField.stringValue = ""
  }

  func controlTextDidBeginEditing(_ notification: Notification) {
    let field = notification.object as AnyObject? === wordField ? "word" : "misspelling"
    log("editing began: \(field) field")
  }

  func control(
    _ control: NSControl,
    textView: NSTextView,
    doCommandBy commandSelector: Selector
  ) -> Bool {
    switch commandSelector {
    case #selector(NSResponder.insertNewline(_:)):
      sync(control, from: textView)
      commit(wordField.stringValue, misspellingField.stringValue)
      return true
    case #selector(NSResponder.cancelOperation(_:)):
      abortEditing()
      return true
    case #selector(NSResponder.insertTab(_:)):
      sync(control, from: textView)
      window?.makeFirstResponder(control === wordField ? misspellingField : wordField)
      log("Tab: responder=\(responderName)")
      return true
    case #selector(NSResponder.insertBacktab(_:)):
      sync(control, from: textView)
      window?.makeFirstResponder(control === misspellingField ? wordField : misspellingField)
      log("Shift-Tab: responder=\(responderName)")
      return true
    default:
      return false
    }
  }

  private func sync(_ control: NSControl, from editor: NSTextView) {
    (control as? NSTextField)?.stringValue = editor.string
  }

  private var responderName: String {
    guard let responder = window?.firstResponder else { return "nil" }
    if let editor = responder as? NSTextView {
      if editor.delegate as AnyObject? === wordField { return "word field editor" }
      if editor.delegate as AnyObject? === misspellingField { return "misspelling field editor" }
    }
    return String(describing: type(of: responder))
  }

  private func configure(_ field: NSTextField, placeholder: String) {
    field.placeholderString = placeholder
    field.delegate = self
    field.bezelStyle = .roundedBezel
    field.font = .systemFont(ofSize: NSFont.systemFontSize)
    field.usesSingleLineMode = true
  }
}

final class Delegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private let focusOnOpen = CommandLine.arguments.contains("--focus-on-open")
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let menu = NSMenu()
  private let quickAddView = QuickAddView(frame: NSRect(x: 0, y: 0, width: 300, height: 98))
  private var keyMonitor: Any?

  func applicationDidFinishLaunching(_: Notification) {
    guard let button = statusItem.button else { fatalError("Status item has no button") }
    button.title = "QA"
    button.toolTip = "Quick Add Menu Spike"
    button.identifier = NSUserInterfaceItemIdentifier("quick-add-menu.status-item")

    let quickAddItem = NSMenuItem(title: "Quick Add", action: nil, keyEquivalent: "")
    quickAddItem.view = quickAddView
    menu.addItem(quickAddItem)
    menu.addItem(.separator())
    menu.addItem(item("Copy Last Transcript", action: #selector(dummyAction(_:))))
    menu.addItem(item("Open Dictionary…", action: #selector(dummyAction(_:))))
    menu.addItem(item("Preferences…", action: #selector(dummyAction(_:))))
    menu.addItem(.separator())
    menu.addItem(item("Quit Spike", action: #selector(quit)))
    menu.delegate = self
    statusItem.menu = menu

    quickAddView.commit = { [weak self] word, misspelling in
      log("COMMIT word=\(String(reflecting: word)) misspelling=\(String(reflecting: misspelling))")
      self?.quickAddView.reset()
      self?.menu.cancelTracking()
    }
    quickAddView.abort = {
      log("ABORT fields cleared; menu remains open")
    }
    // Deliberate probe: menu tracking consumes Escape before this monitor or the field delegate.
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard event.keyCode == 53, let self, self.quickAddView.isEditing else { return event }
      self.quickAddView.abortEditing()
      return nil
    }

    log("READY mode=\(focusOnOpen ? "focus-on-open" : "focus-on-click")")
  }

  func applicationWillTerminate(_: Notification) {
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
  }

  func menuWillOpen(_: NSMenu) {
    log("menuWillOpen fieldWindow=\(quickAddView.wordField.window == nil ? "nil" : "present")")
    if focusOnOpen {
      quickAddView.focusWord(reason: "menuWillOpen")
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [quickAddView] in
        quickAddView.focusWord(reason: "menuWillOpen delayed")
      }
    }
  }

  func menuDidOpen(_: NSMenu) {
    log("menuDidOpen fieldWindow=\(quickAddView.wordField.window == nil ? "nil" : "present")")
    if focusOnOpen {
      quickAddView.focusWord(reason: "menuDidOpen")
      DispatchQueue.main.async { [quickAddView] in
        quickAddView.focusWord(reason: "menuDidOpen async")
      }
    }
  }

  func menuDidClose(_: NSMenu) {
    log("menuDidClose; fields discarded")
    quickAddView.reset()
  }

  func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
    let name = item?.view == quickAddView ? "Quick Add (custom view)" : item?.title ?? "none"
    log("HIGHLIGHT \(name)")
  }

  @objc private func dummyAction(_ sender: NSMenuItem) {
    log("ACTION \(sender.title)")
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }

  private func item(_ title: String, action: Selector) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    return item
  }
}

func log(_ message: String) {
  print("[QuickAddMenu] \(message)")
  fflush(stdout)
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
