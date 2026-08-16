import AppKit

private let contentWidth: CGFloat = 330
private let fieldHeight: CGFloat = 24
private let isIntrinsicProbeEnabled = CommandLine.arguments.contains("--probe-intrinsic")
private let isParityProbeEnabled = CommandLine.arguments.contains("--measure-parity")

func log(_ message: String) {
  print("[QuickAddDisclosure] \(message)")
  fflush(stdout)
}

final class HoverDisclosureButton: NSButton {
  var hoverChanged: (Bool) -> Void = { _ in }

  private var trackingAreaReference: NSTrackingArea?

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
    let trackingArea = NSTrackingArea(
      rect: bounds,
      options: [.activeAlways, .mouseEnteredAndExited],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(trackingArea)
    trackingAreaReference = trackingArea
  }

  override func mouseEntered(with event: NSEvent) {
    hoverChanged(true)
  }

  override func mouseExited(with event: NSEvent) {
    hoverChanged(false)
  }
}

final class MenuCaretIndicator: NSView {
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.textColor.cgColor
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class FormField: NSTextField {
  init(placeholder: String, accessibilityLabel: String) {
    super.init(frame: .zero)
    placeholderString = placeholder
    setAccessibilityLabel(accessibilityLabel)
    bezelStyle = .roundedBezel
    font = .systemFont(ofSize: NSFont.systemFontSize)
    usesSingleLineMode = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

class MenuFormView: NSView, NSTextFieldDelegate {
  var fields: [FormField] = []
  var submit: ([String]) -> Void = { _ in }

  private var caretIndicator: MenuCaretIndicator?
  private var caretTimer: Timer?

  func addField(placeholder: String, accessibilityLabel: String) -> FormField {
    let field = FormField(placeholder: placeholder, accessibilityLabel: accessibilityLabel)
    field.delegate = self
    fields.append(field)
    updateKeyLoop()
    return field
  }

  func focus(_ field: FormField, reason: String) {
    guard let window else {
      log("\(accessibilityLabel() ?? "form") focus \(reason): accepted=false, window=nil")
      return
    }

    if
      let previousEditor = window.firstResponder as? NSTextView,
      let delegate = previousEditor.delegate as AnyObject?,
      let previousField = delegate as? FormField,
      previousField !== field
    {
      previousField.stringValue = previousEditor.string
      previousField.cell?.endEditing(previousEditor)
      previousField.needsDisplay = true
    }

    let editor = window.fieldEditor(true, for: field) as? NSTextView
    if let editor {
      field.cell?.select(
        withFrame: field.bounds,
        in: field,
        editor: editor,
        delegate: field,
        start: field.stringValue.utf16.count,
        length: 0
      )
    }
    let accepted = window.makeFirstResponder(editor ?? field)
    if accepted {
      DispatchQueue.main.async { [weak self, weak field] in
        guard let self, let field else { return }
        showFallbackCaret(for: field)
      }
    }
    log(
      "\(accessibilityLabel() ?? "form") focus \(reason): accepted=\(accepted), "
        + "key=\(window.isKeyWindow), canBecomeKey=\(window.canBecomeKey)"
    )
  }

  func focusFirstField() {
    guard let field = fields.first(where: { !$0.isHidden }) else { return }
    focus(field, reason: "click")
  }

  func reset() {
    fields.forEach { $0.stringValue = "" }
    stopFallbackCaret()
  }

  func syncActiveEditor() {
    if let editor = window?.firstResponder as? NSTextView,
       let field = fields.first(where: { editor.delegate as AnyObject? === $0 })
    {
      field.stringValue = editor.string
    }
  }

  func submitVisibleFields() {
    syncActiveEditor()
    submit(fields.filter { !$0.isHidden }.map(\.stringValue))
  }

  func submitRequested() {
    submitVisibleFields()
  }

  func formValuesDidChange() {}

  override func mouseDown(with event: NSEvent) {
    focusFirstField()
    super.mouseDown(with: event)
  }

  func controlTextDidBeginEditing(_ notification: Notification) {
    guard let field = notification.object as? FormField else { return }
    log("\(accessibilityLabel() ?? "form") editing began: \(field.accessibilityLabel() ?? "field")")
    showFallbackCaret(for: field)
  }

  func controlTextDidChange(_ notification: Notification) {
    guard let field = notification.object as? FormField else { return }
    if
      let editor = window?.firstResponder as? NSTextView,
      editor.delegate as AnyObject? === field
    {
      field.stringValue = editor.string
    }
    updateFallbackCaret(for: field)
    formValuesDidChange()
  }

  func controlTextDidEndEditing(_: Notification) {
    stopFallbackCaret()
  }

  func control(
    _ control: NSControl,
    textView: NSTextView,
    doCommandBy commandSelector: Selector
  ) -> Bool {
    guard let field = control as? FormField else { return false }
    switch commandSelector {
    case #selector(NSResponder.insertNewline(_:)):
      sync(field, from: textView)
      submitRequested()
      return true
    case #selector(NSResponder.insertTab(_:)):
      sync(field, from: textView)
      moveFocus(from: field, backwards: false)
      return true
    case #selector(NSResponder.insertBacktab(_:)):
      sync(field, from: textView)
      moveFocus(from: field, backwards: true)
      return true
    default:
      return false
    }
  }

  func updateKeyLoop() {
    let visibleFields = fields.filter { !$0.isHidden }
    guard !visibleFields.isEmpty else { return }
    for (index, field) in visibleFields.enumerated() {
      field.nextKeyView = visibleFields[(index + 1) % visibleFields.count]
    }
  }

  private func moveFocus(from field: FormField, backwards: Bool) {
    let visibleFields = fields.filter { !$0.isHidden }
    guard let index = visibleFields.firstIndex(of: field), !visibleFields.isEmpty else { return }
    let offset = backwards ? visibleFields.count - 1 : 1
    let next = visibleFields[(index + offset) % visibleFields.count]
    focus(next, reason: backwards ? "Shift-Tab" : "Tab")
  }

  private func sync(_ field: NSTextField, from editor: NSTextView) {
    field.stringValue = editor.string
  }

  private func showFallbackCaret(for field: FormField) {
    guard window?.isKeyWindow == false else { return }
    stopFallbackCaret()

    let indicator = MenuCaretIndicator(frame: .zero)
    caretIndicator = indicator
    guard updateFallbackCaret(for: field, reason: "attach") else {
      caretIndicator = nil
      log("\(accessibilityLabel() ?? "form") fallback caret skipped: invalid field-local rect")
      return
    }

    let timer = Timer(timeInterval: 0.5, repeats: true) { [weak indicator] _ in
      guard let layer = indicator?.layer else { return }
      CATransaction.begin()
      CATransaction.setDisableActions(true)
      layer.isHidden.toggle()
      CATransaction.commit()
    }
    RunLoop.main.add(timer, forMode: .eventTracking)
    RunLoop.main.add(timer, forMode: .common)
    caretTimer = timer
  }

  @discardableResult
  private func updateFallbackCaret(for field: FormField, reason: String = "move") -> Bool {
    guard
      let indicator = caretIndicator,
      let window,
      let editor = window.firstResponder as? NSTextView,
      editor.delegate as AnyObject? === field
    else { return false }

    let selection = editor.selectedRange()
    guard selection.length == 0 else {
      indicator.layer?.isHidden = true
      return true
    }

    let screenRect = editor.firstRect(forCharacterRange: selection, actualRange: nil)
    let windowRect = window.convertFromScreen(screenRect)
    let fieldRect = field.convert(windowRect, from: nil)
    let values = [
      screenRect.minX, screenRect.minY, screenRect.height,
      fieldRect.minX, fieldRect.minY, fieldRect.height,
    ]
    guard values.allSatisfy(\.isFinite), screenRect.height > 4 else {
      log("CARET RECT \(reason) rejected: screen=\(screenRect), field=\(fieldRect)")
      return false
    }

    let candidate = NSRect(
      x: floor(fieldRect.minX),
      y: floor(fieldRect.minY + 2),
      width: 1,
      height: floor(fieldRect.height - 4)
    )
    let permittedBounds = field.bounds.insetBy(dx: -1, dy: -1)
    guard
      candidate.height >= 8,
      candidate.height <= field.bounds.height,
      permittedBounds.intersects(candidate)
    else {
      log(
        "CARET RECT \(reason) rejected: screen=\(screenRect), window=\(windowRect), "
          + "field=\(fieldRect), candidate=\(candidate), bounds=\(field.bounds)"
      )
      return false
    }

    indicator.frame = candidate
    if indicator.superview !== field {
      indicator.removeFromSuperview()
      field.addSubview(indicator, positioned: .above, relativeTo: nil)
    }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    indicator.layer?.isHidden = false
    CATransaction.commit()
    log(
      "CARET RECT \(reason): screen=\(screenRect), window=\(windowRect), "
        + "field=\(fieldRect), final=\(indicator.frame), bounds=\(field.bounds)"
    )
    return true
  }

  private func stopFallbackCaret() {
    caretTimer?.invalidate()
    caretTimer = nil
    caretIndicator?.removeFromSuperview()
    caretIndicator = nil
  }
}

final class AccordionView: MenuFormView {
  enum Stage: String { case collapsed, word, correction }

  private let stack = NSStackView()
  private let headerSelection = NSVisualEffectView()
  private let correctionSelection = NSVisualEffectView()
  private let openButton = HoverDisclosureButton()
  private let correctionButton = HoverDisclosureButton()
  private let addButton = NSButton()
  private let actionRow = NSStackView()
  private let wordField: FormField
  private let misheardField: FormField
  private let headerTopInset: CGFloat = 5
  private var headerTrackingArea: NSTrackingArea?
  private(set) var stage = Stage.collapsed
  var resize: (CGFloat, String) -> Void = { _, _ in }

  override init(frame frameRect: NSRect) {
    wordField = FormField(placeholder: "Word or phrase", accessibilityLabel: "A taught word")
    misheardField = FormField(placeholder: "Misspelling", accessibilityLabel: "A misheard phrase")
    super.init(frame: frameRect)
    setAccessibilityLabel("Add to Dictionary…")

    fields = [wordField, misheardField]
    fields.forEach { $0.delegate = self }

    configureSelection(headerSelection)
    addSubview(headerSelection)
    configureSelection(correctionSelection)
    addSubview(correctionSelection)

    configureDisclosure(
      openButton,
      title: "Add to Dictionary…",
      target: self,
      action: #selector(openWord)
    )
    openButton.hoverChanged = { [weak self] isHovered in
      self?.updateHeaderAppearance(isHovered: isHovered)
    }
    openButton.translatesAutoresizingMaskIntoConstraints = false
    addSubview(openButton)

    configureDisclosure(correctionButton, title: "Misheard as…", target: self, action: #selector(openCorrection))
    correctionButton.hoverChanged = { [weak self] isHovered in
      self?.updateCorrectionAppearance(isHovered: isHovered)
    }
    addButton.title = "Add"
    addButton.target = self
    addButton.action = #selector(add)
    addButton.bezelStyle = .rounded
    actionRow.orientation = .horizontal
    actionRow.alignment = .centerY
    actionRow.addArrangedSubview(addButton)

    correctionButton.isHidden = true
    wordField.isHidden = true
    misheardField.isHidden = true
    actionRow.isHidden = true

    stack.setViews([wordField, correctionButton, misheardField, actionRow], in: .top)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 6
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.isHidden = true
    stack.wantsLayer = true
    addSubview(stack)

    NSLayoutConstraint.activate([
      headerSelection.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
      headerSelection.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
      headerSelection.topAnchor.constraint(equalTo: topAnchor),
      headerSelection.heightAnchor.constraint(equalToConstant: 24),
      openButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
      openButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
      openButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
      openButton.heightAnchor.constraint(equalToConstant: 22),
      correctionSelection.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
      correctionSelection.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
      correctionSelection.centerYAnchor.constraint(equalTo: correctionButton.centerYAnchor),
      correctionSelection.heightAnchor.constraint(equalToConstant: 24),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
      stack.topAnchor.constraint(equalTo: openButton.bottomAnchor, constant: 6),
      stack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6),
      wordField.widthAnchor.constraint(equalTo: stack.widthAnchor),
      wordField.heightAnchor.constraint(equalToConstant: fieldHeight),
      correctionButton.widthAnchor.constraint(equalTo: stack.widthAnchor),
      correctionButton.heightAnchor.constraint(equalToConstant: 22),
      misheardField.widthAnchor.constraint(equalTo: stack.widthAnchor),
      misheardField.heightAnchor.constraint(equalToConstant: fieldHeight),
      actionRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
    ])

    updateHeaderAppearance(isHovered: false)
    updateCorrectionAppearance(isHovered: false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let headerTrackingArea { removeTrackingArea(headerTrackingArea) }
    let trackingArea = NSTrackingArea(
      rect: NSRect(
        x: 5,
        y: bounds.height - 24,
        width: bounds.width - 10,
        height: 24
      ),
      options: [.activeAlways, .mouseEnteredAndExited],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(trackingArea)
    headerTrackingArea = trackingArea
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    if stage == .collapsed, headerSelection.frame.contains(point) { return self }
    if stage == .word, correctionSelection.frame.contains(point) { return self }
    return super.hitTest(point)
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    if stage == .collapsed, headerSelection.frame.contains(point) {
      openWord()
      return
    }
    if stage == .word, correctionSelection.frame.contains(point) {
      openCorrection()
      return
    }
    super.mouseDown(with: event)
  }

  override func mouseEntered(with event: NSEvent) {
    updateHeaderAppearance(isHovered: true)
  }

  override func mouseExited(with event: NSEvent) {
    updateHeaderAppearance(isHovered: false)
  }

  override func submitRequested() {
    attemptSubmit()
  }


  func collapse() {
    stage = .collapsed
    openButton.title = "Add to Dictionary…"
    openButton.isEnabled = true
    headerSelection.isHidden = true
    updateHeaderAppearance(isHovered: false)
    wordField.placeholderString = "Word or phrase"
    wordField.isHidden = true
    correctionButton.isHidden = true
    correctionButton.isEnabled = true
    correctionSelection.isHidden = true
    updateCorrectionAppearance(isHovered: false)
    misheardField.isHidden = true
    actionRow.isHidden = true
    stack.isHidden = true
    reset()
    resizeToFit("frame mutation")
  }

  @objc private func openWord() {
    guard stage == .collapsed else { return }
    stage = .word
    openButton.title = "Add to Dictionary"
    openButton.isEnabled = false
    headerSelection.isHidden = true
    updateHeaderAppearance(isHovered: false)
    stack.isHidden = false
    wordField.isHidden = false
    correctionButton.isHidden = false
    misheardField.isHidden = true
    actionRow.isHidden = false
    updateKeyLoop()
    resizeToFit("frame mutation")
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      focus(wordField, reason: "expanded")
    }
  }

  @objc private func openCorrection() {
    guard stage == .word else { return }
    syncActiveEditor()
    stage = .correction
    wordField.placeholderString = "Correct spelling"
    correctionButton.isEnabled = false
    correctionSelection.isHidden = true
    updateCorrectionAppearance(isHovered: false)
    misheardField.isHidden = false
    updateKeyLoop()
    resizeToFit("nested frame mutation")
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      focus(misheardField, reason: "nested expansion")
    }
  }

  @objc private func add() {
    attemptSubmit()
  }

  private var isValid: Bool {
    !wordField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private func attemptSubmit() {
    syncActiveEditor()
    guard isValid else {
      shakeForm()
      log("A INVALID: form shook; submission ignored")
      return
    }
    submitVisibleFields()
  }

  private func shakeForm() {
    let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
    animation.values = [0, -7, 7, -5, 5, -3, 3, 0]
    animation.duration = 0.35
    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    stack.layer?.add(animation, forKey: "invalid-shake")
  }

  private func configureSelection(_ view: NSVisualEffectView) {
    view.material = .selection
    view.blendingMode = .withinWindow
    view.state = .active
    view.isEmphasized = true
    view.wantsLayer = true
    view.layer?.cornerRadius = 6
    view.layer?.backgroundColor = NSColor(
      deviceRed: 33 / 255,
      green: 73 / 255,
      blue: 162 / 255,
      alpha: 1
    ).cgColor
    view.isHidden = true
    view.translatesAutoresizingMaskIntoConstraints = false
  }

  private func updateHeaderAppearance(isHovered: Bool) {
    let showsSelection = stage == .collapsed && isHovered
    headerSelection.isHidden = !showsSelection
    updateTitle(openButton, selected: showsSelection)
  }

  private func updateCorrectionAppearance(isHovered: Bool) {
    let showsSelection = stage == .word && correctionButton.isEnabled && isHovered
    correctionSelection.isHidden = !showsSelection
    updateTitle(correctionButton, selected: showsSelection)
  }

  private func updateTitle(_ button: NSButton, selected: Bool) {
    let color: NSColor
    if !button.isEnabled {
      color = .disabledControlTextColor
    } else {
      color = selected ? .white : NSColor(deviceWhite: 222 / 255, alpha: 1)
    }
    let paragraphStyle = NSMutableParagraphStyle()
    let textInset: CGFloat = button === openButton ? 11 : 2
    paragraphStyle.firstLineHeadIndent = textInset
    paragraphStyle.headIndent = textInset
    button.attributedTitle = NSAttributedString(
      string: button.title,
      attributes: [
        .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
        .foregroundColor: color,
        .paragraphStyle: paragraphStyle,
      ]
    )
  }

  private func resizeToFit(_ mechanism: String) {
    stack.layoutSubtreeIfNeeded()
    let height = stage == .collapsed
      ? 28
      : ceil(stack.fittingSize.height) + 42
    resize(height, mechanism)
  }
}

final class TwoRowsView: MenuFormView {
  enum Stage: String { case collapsed, word, correction }

  private let stack = NSStackView()
  private let wordButton = NSButton()
  private let correctionButton = NSButton()
  private let misheardField: FormField
  private let taughtField: FormField
  private(set) var stage = Stage.collapsed
  var resize: (CGFloat, String) -> Void = { _, _ in }

  override var intrinsicContentSize: NSSize {
    let height: CGFloat
    switch stage {
    case .collapsed: height = 64
    case .word: height = 66
    case .correction: height = 96
    }
    return NSSize(width: contentWidth, height: height)
  }

  override init(frame frameRect: NSRect) {
    misheardField = FormField(placeholder: "What it heard", accessibilityLabel: "B misheard phrase")
    taughtField = FormField(placeholder: "What it should be", accessibilityLabel: "B taught word")
    super.init(frame: frameRect)
    setAccessibilityLabel("B. Two collapsed rows")

    fields = [misheardField, taughtField]
    fields.forEach { $0.delegate = self }
    configureDisclosure(wordButton, title: "B. Add word…", target: self, action: #selector(openWord))
    configureDisclosure(correctionButton, title: "B. Teach a correction…", target: self, action: #selector(openCorrection))
    stack.setViews([wordButton, correctionButton, misheardField, taughtField], in: .top)
    misheardField.isHidden = true
    taughtField.isHidden = true
    configureStack(stack, in: self)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func collapse() {
    stage = .collapsed
    wordButton.isHidden = false
    correctionButton.isHidden = false
    misheardField.isHidden = true
    taughtField.isHidden = true
    reset()
    invalidateIntrinsicContentSize()
    resize(64, "intrinsic invalidation + fitting size")
  }

  @objc private func openWord() {
    stage = .word
    wordButton.isHidden = true
    correctionButton.isHidden = true
    misheardField.isHidden = true
    taughtField.isHidden = false
    taughtField.placeholderString = "Word to add"
    updateKeyLoop()
    invalidateIntrinsicContentSize()
    resize(66, "intrinsic invalidation + fitting size")
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      focus(taughtField, reason: "expanded")
    }
  }

  @objc private func openCorrection() {
    stage = .correction
    wordButton.isHidden = true
    correctionButton.isHidden = true
    taughtField.placeholderString = "What it should be"
    misheardField.isHidden = false
    taughtField.isHidden = false
    updateKeyLoop()
    invalidateIntrinsicContentSize()
    resize(96, "intrinsic invalidation + fitting size")
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      focus(misheardField, reason: "expanded")
    }
  }
}

final class TrailingToggleView: MenuFormView {
  private let stack = NSStackView()
  private let row = NSStackView()
  private let label = NSTextField(labelWithString: "C. Trailing toggle")
  private let toggle = NSButton()
  private let taughtField: FormField
  private let misheardField: FormField
  private var heightConstraint: NSLayoutConstraint!
  private(set) var correctionVisible = false
  var didChangeHeight: (String) -> Void = { _ in }

  override init(frame frameRect: NSRect) {
    taughtField = FormField(placeholder: "What it should be", accessibilityLabel: "C taught word")
    misheardField = FormField(placeholder: "What it heard", accessibilityLabel: "C misheard phrase")
    super.init(frame: frameRect)
    setAccessibilityLabel("C. Trailing toggle")

    fields = [taughtField, misheardField]
    fields.forEach { $0.delegate = self }
    label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    configureDisclosure(toggle, title: "+ correction", target: self, action: #selector(toggleCorrection))
    toggle.controlSize = .small
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 6
    row.addArrangedSubview(taughtField)
    row.addArrangedSubview(toggle)
    taughtField.widthAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true

    misheardField.isHidden = true
    stack.setViews([label, row, misheardField], in: .top)
    configureStack(stack, in: self)
    translatesAutoresizingMaskIntoConstraints = false
    heightConstraint = heightAnchor.constraint(equalToConstant: 86)
    heightConstraint.isActive = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func resetDisclosure() {
    correctionVisible = false
    toggle.title = "+ correction"
    misheardField.isHidden = true
    heightConstraint.constant = 86
    reset()
    updateKeyLoop()
  }

  @objc private func toggleCorrection() {
    correctionVisible.toggle()
    toggle.title = correctionVisible ? "− correction" : "+ correction"
    misheardField.isHidden = !correctionVisible
    heightConstraint.constant = correctionVisible ? 116 : 86
    updateKeyLoop()
    needsUpdateConstraints = true
    layoutSubtreeIfNeeded()
    didChangeHeight("Auto Layout height constraint")
    if correctionVisible {
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        focus(misheardField, reason: "toggle")
      }
    }
  }
}

final class CorrectionFormView: MenuFormView {
  private let misheardField: FormField
  private let taughtField: FormField

  init(label: String) {
    misheardField = FormField(placeholder: "What it heard", accessibilityLabel: "\(label) misheard phrase")
    taughtField = FormField(placeholder: "What it should be", accessibilityLabel: "\(label) taught word")
    super.init(frame: NSRect(x: 0, y: 0, width: contentWidth, height: 96))
    setAccessibilityLabel(label)
    fields = [misheardField, taughtField]
    fields.forEach { $0.delegate = self }

    let heading = NSTextField(labelWithString: label)
    heading.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    let stack = NSStackView(views: [heading, misheardField, taughtField])
    configureStack(stack, in: self)
    updateKeyLoop()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class PopoverController: NSViewController, NSTextFieldDelegate {
  private let misheardField = FormField(placeholder: "What it heard", accessibilityLabel: "E misheard phrase")
  private let taughtField = FormField(placeholder: "What it should be", accessibilityLabel: "E taught word")
  var submit: (String, String) -> Void = { _, _ in }
  var dismiss: () -> Void = {}

  override func loadView() {
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 330, height: 120))
    let heading = NSTextField(labelWithString: "E. Popover — Teach a correction")
    heading.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    misheardField.delegate = self
    taughtField.delegate = self
    misheardField.nextKeyView = taughtField
    taughtField.nextKeyView = misheardField
    let stack = NSStackView(views: [heading, misheardField, taughtField])
    configureStack(stack, in: container)
    view = container
  }

  override func viewDidAppear() {
    super.viewDidAppear()
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      let accepted = self.view.window?.makeFirstResponder(self.misheardField) ?? false
      log("E. Popover focus opened: accepted=\(accepted)")
    }
  }

  func reset() {
    misheardField.stringValue = ""
    taughtField.stringValue = ""
  }

  func control(
    _ control: NSControl,
    textView: NSTextView,
    doCommandBy commandSelector: Selector
  ) -> Bool {
    switch commandSelector {
    case #selector(NSResponder.insertNewline(_:)):
      (control as? NSTextField)?.stringValue = textView.string
      submit(misheardField.stringValue, taughtField.stringValue)
      return true
    case #selector(NSResponder.cancelOperation(_:)):
      reset()
      dismiss()
      log("E ABORT: Escape closed popover")
      return true
    case #selector(NSResponder.insertTab(_:)):
      (control as? NSTextField)?.stringValue = textView.string
      view.window?.makeFirstResponder(control === misheardField ? taughtField : misheardField)
      return true
    case #selector(NSResponder.insertBacktab(_:)):
      (control as? NSTextField)?.stringValue = textView.string
      view.window?.makeFirstResponder(control === taughtField ? misheardField : taughtField)
      return true
    default:
      return false
    }
  }
}

private func configureDisclosure(_ button: NSButton, title: String, target: AnyObject, action: Selector) {
  button.title = title
  button.target = target
  button.action = action
  button.bezelStyle = .inline
  button.isBordered = false
  button.font = .systemFont(ofSize: NSFont.systemFontSize)
  button.alignment = .left
  button.setButtonType(.momentaryPushIn)
}

private func configureStack(_ stack: NSStackView, in container: NSView) {
  stack.orientation = .vertical
  stack.alignment = .leading
  stack.spacing = 6
  stack.translatesAutoresizingMaskIntoConstraints = false
  container.addSubview(stack)
  NSLayoutConstraint.activate([
    stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
    stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
    stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
    stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -8),
  ])
  for view in stack.arrangedSubviews where view is NSTextField {
    view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    if let field = view as? FormField {
      field.heightAnchor.constraint(equalToConstant: fieldHeight).isActive = true
    }
  }
}

final class Delegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private let menu = NSMenu()
  private let accordion = AccordionView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: 28))
  private let twoRows = TwoRowsView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: 64))
  private let trailing = TrailingToggleView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: 86))
  private let submenuForm = CorrectionFormView(label: "D. Submenu — Teach a correction")
  private let popover = NSPopover()
  private let popoverController = PopoverController()
  private var closeReason = "ordinary dismissal"

  func applicationDidFinishLaunching(_: Notification) {
    guard let button = statusItem.button else { fatalError("Status item has no button") }
    button.title = "QD"
    button.toolTip = "Quick-add disclosure comparison"
    button.identifier = NSUserInterfaceItemIdentifier("quick-add-disclosure.status-item")

    menu.minimumWidth = contentWidth
    menu.delegate = self
    menu.addItem(viewItem(accordion))
    if isParityProbeEnabled {
      menu.addItem(item("Add to Dictionary…", action: #selector(dummyAction(_:))))
    }
    menu.addItem(.separator())
    menu.addItem(viewItem(twoRows))
    menu.addItem(.separator())
    menu.addItem(viewItem(trailing))
    menu.addItem(.separator())

    let submenuItem = NSMenuItem(title: "D. Submenu — Teach a correction…", action: nil, keyEquivalent: "")
    let correctionSubmenu = NSMenu(title: "D. Submenu")
    correctionSubmenu.addItem(viewItem(submenuForm))
    submenuItem.submenu = correctionSubmenu
    menu.addItem(submenuItem)

    menu.addItem(item("E. Popover — Teach a correction…", action: #selector(openPopover)))
    menu.addItem(.separator())
    menu.addItem(item("Ordinary sibling item", action: #selector(dummyAction(_:))))
    menu.addItem(item("Quit Spike", action: #selector(quit)))
    statusItem.menu = menu

    accordion.resize = { [weak self, weak accordion] height, mechanism in
      guard let self, let accordion else { return }
      self.resize(accordion, to: height, mechanism: "A \(mechanism)")
    }
    accordion.submit = { [weak self] values in
      if values.count == 1 || values[1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        self?.commit("A VOCABULARY taught=\(quoted(values[0]))")
      } else {
        self?.commit("A CORRECTION heard=\(quoted(values[1])) taught=\(quoted(values[0]))")
      }
    }
    twoRows.resize = { [weak self, weak twoRows] height, mechanism in
      guard let self, let twoRows else { return }
      if isIntrinsicProbeEnabled {
        self.probeIntrinsicResize(twoRows, requested: height, mechanism: "B \(mechanism)")
      } else {
        self.resize(twoRows, to: height, mechanism: "B explicit frame")
      }
    }
    trailing.didChangeHeight = { [weak self, weak trailing] mechanism in
      guard let self, let trailing else { return }
      self.measureResize(trailing, requested: trailing.correctionVisible ? 116 : 86, mechanism: "C \(mechanism)")
    }

    twoRows.submit = { [weak self, weak twoRows] values in
      guard let stage = twoRows?.stage else { return }
      if stage == .word { self?.commit("B WORD taught=\(quoted(values[0]))") }
      else { self?.commit("B CORRECTION heard=\(quoted(values[0])) taught=\(quoted(values[1]))") }
    }
    trailing.submit = { [weak self, weak trailing] values in
      if trailing?.correctionVisible == true {
        self?.commit("C CORRECTION taught=\(quoted(values[0])) heard=\(quoted(values[1])) [word-first contrast]")
      } else {
        self?.commit("C WORD taught=\(quoted(values[0]))")
      }
    }
    submenuForm.submit = { [weak self] values in
      self?.commit("D CORRECTION heard=\(quoted(values[0])) taught=\(quoted(values[1]))")
    }

    popover.behavior = .transient
    popover.contentViewController = popoverController
    popover.contentSize = NSSize(width: 330, height: 120)
    popoverController.submit = { [weak self] heard, taught in
      log("SUBMIT E CORRECTION heard=\(quoted(heard)) taught=\(quoted(taught))")
      self?.popoverController.reset()
      self?.popover.performClose(nil)
    }
    popoverController.dismiss = { [weak self] in self?.popover.performClose(nil) }

    log("READY macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    log("Click QD; A=frame, B=\(isIntrinsicProbeEnabled ? "intrinsic probe + frame fallback" : "frame"), C=height constraint")
  }

  func menuWillOpen(_: NSMenu) {
    closeReason = "ordinary dismissal"
    log("MENU OPEN bounds=\(boundsDescription(menuWindow))")
  }

  func menuDidClose(_: NSMenu) {
    log("MENU CLOSED reason=\(closeReason)")
    accordion.collapse()
    twoRows.collapse()
    trailing.resetDisclosure()
    submenuForm.reset()
  }

  func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
    log("HIGHLIGHT \(item?.title.isEmpty == false ? item!.title : item?.view?.accessibilityLabel() ?? "none")")
  }

  private func resize(_ view: NSView, to height: CGFloat, mechanism: String) {
    let beforeView = view.frame
    let beforeWindow = menuWindow?.frame
    view.setFrameSize(NSSize(width: contentWidth, height: height))
    view.needsLayout = true
    view.layoutSubtreeIfNeeded()
    menu.update()
    log("RESIZE REQUEST \(mechanism): view \(beforeView.size) → \(view.frame.size), menu \(string(beforeWindow))")
    measureResize(view, requested: height, mechanism: mechanism)
  }

  private func probeIntrinsicResize(_ view: NSView, requested: CGFloat, mechanism: String) {
    let beforeView = view.frame
    let beforeWindow = menuWindow?.frame
    view.needsUpdateConstraints = true
    view.needsLayout = true
    menu.update()
    log("RESIZE REQUEST \(mechanism): intrinsic=\(view.intrinsicContentSize.height), view=\(beforeView.height), menu=\(string(beforeWindow))")
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak view] in
      guard let self, let view else { return }
      if abs(view.frame.height - requested) < 1 {
        log("RESIZE RESULT \(mechanism): intrinsic invalidation resized live to \(view.frame.height), menu=\(boundsDescription(self.menuWindow))")
      } else {
        log("RESIZE RESULT \(mechanism): intrinsic invalidation did not resize (still \(view.frame.height)); applying explicit-frame fallback")
        self.resize(view, to: requested, mechanism: "B explicit-frame fallback")
      }
    }
  }

  private func measureResize(_ view: NSView, requested: CGFloat, mechanism: String) {
    let immediateView = view.frame
    let immediateWindow = menuWindow?.frame
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak view] in
      guard let self, let view else { return }
      let actualHeight = view.frame.height
      let result = abs(actualHeight - requested) < 1 ? "view accepted" : "view rejected"
      log("RESIZE RESULT \(mechanism): requested=\(requested), immediate=\(immediateView.height), delayed=\(actualHeight) [\(result)], menu immediate=\(string(immediateWindow)) delayed=\(boundsDescription(self.menuWindow))")
    }
  }

  private var menuWindow: NSWindow? {
    accordion.window ?? twoRows.window ?? trailing.window
  }

  private func commit(_ message: String) {
    log("SUBMIT \(message)")
    closeReason = "Return submitted"
    accordion.reset()
    twoRows.reset()
    trailing.reset()
    submenuForm.reset()
    menu.cancelTracking()
  }

  @objc private func openPopover() {
    guard let button = statusItem.button else { return }
    closeReason = "opened E popover"
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
      log("E POPOVER OPEN")
    }
  }

  @objc private func dummyAction(_ sender: NSMenuItem) {
    log("ACTION \(sender.title)")
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }

  private func viewItem(_ view: NSView) -> NSMenuItem {
    let item = NSMenuItem(title: view.accessibilityLabel() ?? "", action: nil, keyEquivalent: "")
    item.view = view
    return item
  }

  private func item(_ title: String, action: Selector) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    return item
  }
}

private func quoted(_ value: String) -> String { String(reflecting: value) }

private func string(_ frame: NSRect?) -> String {
  guard let frame else { return "nil" }
  return "x=\(Int(frame.minX)) y=\(Int(frame.minY)) w=\(Int(frame.width)) h=\(Int(frame.height))"
}

private func boundsDescription(_ window: NSWindow?) -> String { string(window?.frame) }

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
