import AppKit

// MARK: - DictionaryQuickAddCopy

enum DictionaryQuickAddCopy {
  static let recognitionOffMarker = "recognition off"
}

// MARK: - DictionaryQuickAddMarker

private final class DictionaryQuickAddMarker: NSTextField {
  // MARK: Lifecycle

  init() {
    super.init(frame: .zero)
    stringValue = DictionaryQuickAddCopy.recognitionOffMarker
    isEditable = false
    isBordered = false
    drawsBackground = false
    font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    textColor = .systemOrange
    alignment = .right
    lineBreakMode = .byClipping
    setContentCompressionResistancePriority(.required, for: .horizontal)
    setAccessibilityIdentifier(AccessibilityID.menuQuickAddRecognitionOff)
    setAccessibilityLabel("Recognition status")
    setAccessibilityValue(DictionaryQuickAddCopy.recognitionOffMarker)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: Internal

  override func hitTest(_: NSPoint) -> NSView? {
    nil
  }
}

// MARK: - DictionaryQuickAddDisclosureButton

private final class DictionaryQuickAddDisclosureButton: NSButton {
  // MARK: Internal

  var hoverChanged: (Bool) -> Void = { _ in }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingAreaReference {
      removeTrackingArea(trackingAreaReference)
    }
    let trackingArea = NSTrackingArea(
      rect: bounds,
      options: [.activeAlways, .mouseEnteredAndExited],
      owner: self,
      userInfo: nil,
    )
    addTrackingArea(trackingArea)
    trackingAreaReference = trackingArea
  }

  override func mouseEntered(with _: NSEvent) {
    hoverChanged(true)
  }

  override func mouseExited(with _: NSEvent) {
    hoverChanged(false)
  }

  // MARK: Private

  private var trackingAreaReference: NSTrackingArea?
}

// MARK: - DictionaryQuickAddCaret

private final class DictionaryQuickAddCaret: NSView {
  // MARK: Lifecycle

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    updateColor()
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: Internal

  override func hitTest(_: NSPoint) -> NSView? {
    nil
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateColor()
  }

  // MARK: Private

  private func updateColor() {
    effectiveAppearance.performAsCurrentDrawingAppearance {
      layer?.backgroundColor = NSColor.labelColor.cgColor
    }
  }
}

// MARK: - DictionaryQuickAddField

private final class DictionaryQuickAddField: NSTextField {
  init(placeholder: String, accessibilityLabel: String, identifier: String) {
    super.init(frame: .zero)
    placeholderString = placeholder
    setAccessibilityLabel(accessibilityLabel)
    setAccessibilityIdentifier(identifier)
    bezelStyle = .roundedBezel
    font = .systemFont(ofSize: NSFont.systemFontSize)
    usesSingleLineMode = true
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

// MARK: - DictionaryQuickAddView

final class DictionaryQuickAddView: NSView, NSTextFieldDelegate {
  // MARK: Lifecycle

  override init(frame frameRect: NSRect) {
    wordField = DictionaryQuickAddField(
      placeholder: DictionaryFieldCopy.word,
      accessibilityLabel: DictionaryFieldCopy.word,
      identifier: AccessibilityID.menuQuickAddWord,
    )
    misspellingField = DictionaryQuickAddField(
      placeholder: DictionaryFieldCopy.misspelling,
      accessibilityLabel: DictionaryFieldCopy.misspelling,
      identifier: AccessibilityID.menuQuickAddMisspelling,
    )
    super.init(frame: frameRect)

    // The wrapper NSMenu hosts this item in owns the width; the mask keeps the view stretched to
    // it through every resize, so nothing has to re-sync geometry by hand and `resizeToFit` is
    // left owning exactly one axis.
    autoresizingMask = [.width]
    setAccessibilityLabel("Add to Dictionary…")
    wordField.delegate = self
    misspellingField.delegate = self

    configureSelection(headerSelection)
    addSubview(headerSelection)
    configureSelection(correctionSelection)
    addSubview(correctionSelection)

    configureDisclosure(
      headerButton,
      title: "Add to Dictionary…",
      identifier: AccessibilityID.menuQuickAddHeader,
      action: #selector(openWord),
    )
    // The container's tracking area is the single writer of isHeaderHovered; a second writer on
    // the button strobes the pill at every internal boundary crossing.
    headerButton.translatesAutoresizingMaskIntoConstraints = false
    addSubview(headerButton)

    configureDisclosure(
      correctionButton,
      title: "Misheard as…",
      identifier: AccessibilityID.menuQuickAddDisclosure,
      action: #selector(openCorrection),
    )
    correctionButton.hoverChanged = { [weak self] in self?.isCorrectionHovered = $0 }

    addButton.title = "Add"
    addButton.target = self
    addButton.action = #selector(add)
    addButton.bezelStyle = .rounded
    addButton.setAccessibilityIdentifier(AccessibilityID.menuQuickAddSubmit)
    addButton.setAccessibilityLabel("Add to Dictionary")

    actionRow.orientation = .horizontal
    actionRow.alignment = .centerY
    actionSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
    actionRow.addArrangedSubview(addButton)
    actionRow.addArrangedSubview(actionSpacer)

    recognitionOffMarker.translatesAutoresizingMaskIntoConstraints = false
    addSubview(recognitionOffMarker)

    failureLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    failureLabel.textColor = .secondaryLabelColor
    failureLabel.lineBreakMode = .byWordWrapping
    failureLabel.maximumNumberOfLines = 2
    failureLabel.setAccessibilityIdentifier(AccessibilityID.menuQuickAddFailure)
    failureLabel.setAccessibilityLabel("Dictionary error")

    stack.setViews(
      [wordField, correctionButton, misspellingField, actionRow, failureLabel],
      in: .top,
    )
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = Metrics.spacing
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.wantsLayer = true
    addSubview(stack)

    NSLayoutConstraint.activate([
      headerSelection.leadingAnchor.constraint(
        equalTo: leadingAnchor, constant: Metrics.rowInset,
      ),
      headerSelection.trailingAnchor.constraint(
        equalTo: trailingAnchor, constant: -Metrics.rowInset,
      ),
      headerSelection.topAnchor.constraint(equalTo: topAnchor),
      headerSelection.heightAnchor.constraint(equalToConstant: Metrics.selectionHeight),
      headerButton.leadingAnchor.constraint(
        equalTo: leadingAnchor, constant: Metrics.rowInset,
      ),
      headerButton.trailingAnchor.constraint(
        equalTo: trailingAnchor, constant: -Metrics.rowInset,
      ),
      // The header centers in the collapsed row band and keeps that position when the form
      // expands below it, so the collapsed→expanded morph never moves the title.
      headerButton.centerYAnchor.constraint(
        equalTo: topAnchor, constant: Metrics.collapsedHeight / 2,
      ),
      headerButton.heightAnchor.constraint(equalToConstant: Metrics.buttonHeight),
      recognitionOffMarker.trailingAnchor.constraint(
        equalTo: trailingAnchor, constant: -Metrics.contentInset,
      ),
      recognitionOffMarker.centerYAnchor.constraint(equalTo: headerButton.centerYAnchor),
      correctionSelection.leadingAnchor.constraint(
        equalTo: leadingAnchor, constant: Metrics.rowInset,
      ),
      correctionSelection.trailingAnchor.constraint(
        equalTo: trailingAnchor, constant: -Metrics.rowInset,
      ),
      correctionSelection.centerYAnchor.constraint(equalTo: correctionButton.centerYAnchor),
      correctionSelection.heightAnchor.constraint(equalToConstant: Metrics.selectionHeight),
      stack.leadingAnchor.constraint(
        equalTo: leadingAnchor, constant: Metrics.contentInset,
      ),
      stack.trailingAnchor.constraint(
        equalTo: trailingAnchor, constant: -Metrics.contentInset,
      ),
      stack.topAnchor.constraint(equalTo: headerButton.bottomAnchor, constant: Metrics.spacing),
      // The bottom guard only describes the expanded form. In the 24pt collapsed row the hidden
      // stack cannot fit, and at required priority autolayout would break an arbitrary sibling
      // constraint instead — once the header's centerY, which emptied the row.
      expandedStackBottomGuard,
      wordField.widthAnchor.constraint(equalTo: stack.widthAnchor),
      wordField.heightAnchor.constraint(equalToConstant: Metrics.fieldHeight),
      correctionButton.widthAnchor.constraint(equalTo: stack.widthAnchor),
      correctionButton.heightAnchor.constraint(equalToConstant: Metrics.buttonHeight),
      misspellingField.widthAnchor.constraint(equalTo: stack.widthAnchor),
      misspellingField.heightAnchor.constraint(equalToConstant: Metrics.fieldHeight),
      actionRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
      failureLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
    ])

    collapse()
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // MARK: Internal

  static let width = Metrics.width

  var refuses: () -> String? = { nil }
  var submit: (String, String) -> Void = { _, _ in }

  var improvesRecognition = true {
    didSet { render() }
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    render()
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let headerTrackingArea {
      removeTrackingArea(headerTrackingArea)
    }
    // .inVisibleRect keeps the area glued to the wrapper-filling bounds through every
    // frame-driven resize, so hover has exactly one writer and one geometry.
    let trackingArea = NSTrackingArea(
      rect: .zero,
      options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
      owner: self,
      userInfo: nil,
    )
    addTrackingArea(trackingArea)
    headerTrackingArea = trackingArea
  }

  override func mouseEntered(with _: NSEvent) {
    if stage == .collapsed {
      isHeaderHovered = true
    }
  }

  override func mouseExited(with _: NSEvent) {
    isHeaderHovered = false
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    rowAction(at: point) == nil ? super.hitTest(point) : self
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    if let action = rowAction(at: point) {
      action()
      return
    }
    focusFirstField()
    super.mouseDown(with: event)
  }

  func collapse() {
    stage = .collapsed
    isHeaderHovered = false
    reset()
  }

  func controlTextDidBeginEditing(_ notification: Notification) {
    guard let field = notification.object as? DictionaryQuickAddField else {
      return
    }
    showFallbackCaret(for: field)
  }

  func controlTextDidChange(_ notification: Notification) {
    guard let field = notification.object as? DictionaryQuickAddField else {
      return
    }
    if let editor = window?.firstResponder as? NSTextView,
       editor.delegate as AnyObject? === field
    {
      field.stringValue = editor.string
    }
    updateFallbackCaret(for: field)
    clearFailure()
  }

  func controlTextDidEndEditing(_: Notification) {
    stopFallbackCaret()
  }

  func control(
    _ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector,
  ) -> Bool {
    guard let field = control as? DictionaryQuickAddField else {
      return false
    }
    switch commandSelector {
    case #selector(NSResponder.insertNewline(_:)):
      sync(field, from: textView)
      attemptSubmit()
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

  // MARK: Private

  private enum Stage {
    case collapsed
    case word
    case correction
  }

  private enum Metrics {
    /// Ticket 34 measured the 330pt menu width and 42pt form chrome; native-row probing pins the
    /// collapsed row band to 24pt. Visual insets are edge-relative to the wrapper-filling view.
    static let width: CGFloat = 330
    static let collapsedHeight: CGFloat = 24
    static let expandedChromeHeight: CGFloat = 42
    // Ticket 34 aligned the selection, buttons, and content column against a native sibling.
    static let selectionHeight: CGFloat = 24
    static let rowInset: CGFloat = 5
    static let buttonHeight: CGFloat = 22
    static let contentInset: CGFloat = 14
    static let spacing: CGFloat = 6
    static let fieldHeight: CGFloat = 24
    static let selectionCornerRadius: CGFloat = 6
    // Half-second blinking matches AppKit's apparent insertion-caret cadence under menu tracking.
    static let caretBlinkInterval: TimeInterval = 0.5
    static let caretVerticalInset: CGFloat = 2
    static let minimumCaretHeight: CGFloat = 8
    static let minimumMeasuredLineHeight: CGFloat = 4
    // Ticket 34 settled on the standard 350ms diminishing x-translation shake.
    static let shakeDuration: TimeInterval = 0.35
    static let shakeOffsets = [0, -7, 7, -5, 5, -3, 3, 0]

    // Ticket 34 aligned these attributed-title insets against the native and nested sibling glyphs.
    static let headerTitleInset: CGFloat = 11
    static let correctionTitleInset: CGFloat = 2
  }

  private let stack = NSStackView()
  private let headerSelection = NSVisualEffectView()
  private let correctionSelection = NSVisualEffectView()
  private let headerButton = DictionaryQuickAddDisclosureButton()
  private let correctionButton = DictionaryQuickAddDisclosureButton()
  private let addButton = NSButton()
  private let actionRow = NSStackView()
  private let actionSpacer = NSView()
  private let recognitionOffMarker = DictionaryQuickAddMarker()
  private let wordField: DictionaryQuickAddField
  private let misspellingField: DictionaryQuickAddField
  private let failureLabel = NSTextField(wrappingLabelWithString: "")
  private var caretIndicator: DictionaryQuickAddCaret?
  private var caretTimer: Timer?
  private var headerTrackingArea: NSTrackingArea?

  private lazy var expandedStackBottomGuard: NSLayoutConstraint = {
    let constraint = stack.bottomAnchor.constraint(
      lessThanOrEqualTo: bottomAnchor, constant: -Metrics.spacing,
    )
    constraint.priority = .defaultHigh
    return constraint
  }()

  private var isHeaderHovered = false {
    didSet { updateHeaderAppearance(isHovered: isHeaderHovered) }
  }

  private var isCorrectionHovered = false {
    didSet { updateCorrectionAppearance(isHovered: isCorrectionHovered) }
  }

  private var stage = Stage.collapsed {
    didSet { render() }
  }

  @objc private func openWord() {
    guard stage == .collapsed else {
      return
    }
    stage = .word
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        return
      }
      focus(wordField)
    }
  }

  @objc private func openCorrection() {
    guard stage == .word else {
      return
    }
    syncActiveEditor()
    stage = .correction
    DispatchQueue.main.async { [weak self] in
      guard let self else {
        return
      }
      focus(misspellingField)
    }
  }

  @objc private func add() {
    attemptSubmit()
  }

  private func render() {
    let isCollapsed = stage == .collapsed
    let isCorrection = stage == .correction

    headerButton.title = isCollapsed ? "Add to Dictionary…" : "Add to Dictionary"
    headerButton.isEnabled = isCollapsed
    stack.isHidden = isCollapsed
    wordField.isHidden = isCollapsed
    correctionButton.isHidden = isCollapsed
    correctionButton.isEnabled = stage == .word
    misspellingField.isHidden = !isCorrection
    actionRow.isHidden = isCollapsed
    recognitionOffMarker.isHidden = improvesRecognition

    let wordLabel = isCorrection ? DictionaryFieldCopy.correction : DictionaryFieldCopy.word
    wordField.placeholderString = wordLabel
    wordField.setAccessibilityLabel(wordLabel)

    updateHeaderAppearance(isHovered: isHeaderHovered)
    updateCorrectionAppearance(isHovered: isCorrectionHovered)
    updateRecognitionOffMarkerAppearance()
    resizeToFit()
  }

  private func reset() {
    wordField.stringValue = ""
    misspellingField.stringValue = ""
    failureLabel.stringValue = ""
    failureLabel.isHidden = true
    isHeaderHovered = false
    isCorrectionHovered = false
    stopFallbackCaret()
    resizeToFit()
  }

  private func rowAction(at point: NSPoint) -> (() -> Void)? {
    if stage == .collapsed, bounds.contains(point) {
      return { [weak self] in self?.openWord() }
    }
    if stage == .word, correctionSelection.frame.contains(point) {
      return { [weak self] in self?.openCorrection() }
    }
    return nil
  }

  private func attemptSubmit() {
    syncActiveEditor()
    let misspelling = stage == .correction ? misspellingField.stringValue : ""
    let draft = DictionaryFeature.Draft(
      text: wordField.stringValue,
      misspelling: misspelling,
      isCorrection: !misspelling.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
    )
    guard draft.canSave else {
      shakeForm()
      return
    }
    if let refusal = refuses() {
      failureLabel.stringValue = refusal
      failureLabel.isHidden = false
      resizeToFit()
      return
    }
    submit(wordField.stringValue, misspelling)
    enclosingMenuItem?.menu?.cancelTracking()
  }

  private func clearFailure() {
    guard !failureLabel.isHidden else {
      return
    }
    failureLabel.stringValue = ""
    failureLabel.isHidden = true
    resizeToFit()
  }

  private func shakeForm() {
    let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
    animation.values = Metrics.shakeOffsets
    animation.duration = Metrics.shakeDuration
    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    stack.layer?.add(animation, forKey: "invalid-shake")
  }

  private func focusFirstField() {
    guard let field = [wordField, misspellingField].first(where: { !$0.isHidden }) else {
      return
    }
    focus(field)
  }

  private func focus(_ field: DictionaryQuickAddField) {
    guard let window else {
      return
    }
    // A menu window owns one field editor; its old cell must end editing or it draws no value or
    // placeholder.
    if let previousEditor = window.firstResponder as? NSTextView,
       let previousField = previousEditor.delegate as AnyObject? as? NSTextField,
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
        length: 0,
      )
    }
    if window.makeFirstResponder(editor ?? field) {
      DispatchQueue.main.async { [weak self, weak field] in
        guard let self, let field else {
          return
        }
        showFallbackCaret(for: field)
      }
    }
  }

  private func moveFocus(from field: DictionaryQuickAddField, backwards: Bool) {
    let visibleFields = [wordField, misspellingField].filter { !$0.isHidden }
    guard let index = visibleFields.firstIndex(of: field) else {
      return
    }
    let offset = backwards ? visibleFields.count - 1 : 1
    focus(visibleFields[(index + offset) % visibleFields.count])
  }

  private func syncActiveEditor() {
    guard let editor = window?.firstResponder as? NSTextView,
          let field = editor.delegate as AnyObject? as? DictionaryQuickAddField
    else {
      return
    }
    field.stringValue = editor.string
  }

  private func sync(_ field: NSTextField, from editor: NSTextView) {
    field.stringValue = editor.string
  }

  private func showFallbackCaret(for field: DictionaryQuickAddField) {
    guard window?.isKeyWindow == false else {
      return
    }
    stopFallbackCaret()
    updateFallbackCaret(for: field)
  }

  @discardableResult
  private func updateFallbackCaret(for field: DictionaryQuickAddField) -> Bool {
    guard let window,
          let editor = window.firstResponder as? NSTextView,
          editor.delegate as AnyObject? === field
    else {
      return false
    }

    let indicator: DictionaryQuickAddCaret
    if let caretIndicator {
      indicator = caretIndicator
    } else {
      indicator = DictionaryQuickAddCaret(frame: .zero)
      caretIndicator = indicator
    }

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
    guard values.allSatisfy(\.isFinite),
          screenRect.height > Metrics.minimumMeasuredLineHeight
    else {
      return false
    }

    let candidate = NSRect(
      x: floor(fieldRect.minX),
      y: floor(fieldRect.minY + Metrics.caretVerticalInset),
      width: 1,
      height: floor(fieldRect.height - 2 * Metrics.caretVerticalInset),
    )
    let permittedBounds = field.bounds.insetBy(dx: -1, dy: -1)
    guard candidate.height >= Metrics.minimumCaretHeight,
          candidate.height <= field.bounds.height,
          permittedBounds.intersects(candidate)
    else {
      return false
    }

    indicator.frame = candidate
    if indicator.superview !== field {
      indicator.removeFromSuperview()
      // The menu never becomes key, so this field-local layer supplies the caret without
      // invalidating the whole menu.
      field.addSubview(indicator, positioned: .above, relativeTo: nil)
    }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    indicator.layer?.isHidden = false
    CATransaction.commit()
    startCaretTimerIfNeeded()
    return true
  }

  private func startCaretTimerIfNeeded() {
    guard caretTimer == nil else {
      return
    }
    let timer = Timer(
      timeInterval: Metrics.caretBlinkInterval,
      target: self,
      selector: #selector(toggleFallbackCaret),
      userInfo: nil,
      repeats: true,
    )
    RunLoop.main.add(timer, forMode: .eventTracking)
    caretTimer = timer
  }

  @objc private func toggleFallbackCaret() {
    guard let layer = caretIndicator?.layer else {
      return
    }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer.isHidden.toggle()
    CATransaction.commit()
  }

  private func stopFallbackCaret() {
    caretTimer?.invalidate()
    caretTimer = nil
    caretIndicator?.removeFromSuperview()
    caretIndicator = nil
  }

  private func configureSelection(_ view: NSVisualEffectView) {
    view.material = .selection
    view.blendingMode = .withinWindow
    view.state = .active
    view.isEmphasized = true
    view.wantsLayer = true
    view.layer?.cornerRadius = Metrics.selectionCornerRadius
    view.layer?.masksToBounds = true
    view.translatesAutoresizingMaskIntoConstraints = false
  }

  private func configureDisclosure(
    _ button: DictionaryQuickAddDisclosureButton,
    title: String,
    identifier: String,
    action: Selector,
  ) {
    button.title = title
    button.target = self
    button.action = action
    button.bezelStyle = .inline
    button.isBordered = false
    // A frontmost settings window otherwise lends this menu-hosted button a clipped edge-only ring.
    button.focusRingType = .none
    button.font = .systemFont(ofSize: NSFont.systemFontSize)
    button.alignment = .left
    button.setButtonType(.momentaryPushIn)
    button.setAccessibilityIdentifier(identifier)
    button.setAccessibilityLabel(title)
  }

  private func updateHeaderAppearance(isHovered: Bool) {
    let showsSelection = stage == .collapsed && isHovered
    headerSelection.isHidden = !showsSelection
    // The header button is already in the accessibility tree and already changes with hover, so
    // it publishes the state rather than a clear one-point label existing to be read by a test.
    headerButton.setAccessibilityValue("Hover \(showsSelection ? "on" : "off")")
    updateTitle(headerButton, selected: showsSelection)
  }

  private func updateCorrectionAppearance(isHovered: Bool) {
    let showsSelection = stage == .word && isHovered
    correctionSelection.isHidden = !showsSelection
    updateTitle(correctionButton, selected: showsSelection)
  }

  /// The marker sits on the header row in both stages, so only the collapsed row's selection
  /// pill can ever run underneath it.
  private func updateRecognitionOffMarkerAppearance() {
    recognitionOffMarker.textColor = isHeaderHovered && stage == .collapsed
      ? .selectedMenuItemTextColor
      : .systemOrange
  }

  private func updateTitle(_ button: NSButton, selected: Bool) {
    let color: NSColor =
      if !button.isEnabled {
        .disabledControlTextColor
      } else {
        selected ? .selectedMenuItemTextColor : .labelColor
      }
    let paragraphStyle = NSMutableParagraphStyle()
    let textInset = button === headerButton
      ? Metrics.headerTitleInset
      : Metrics.correctionTitleInset
    paragraphStyle.firstLineHeadIndent = textInset
    paragraphStyle.headIndent = textInset
    button.attributedTitle = NSAttributedString(
      string: button.title,
      attributes: [
        .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
        .foregroundColor: color,
        .paragraphStyle: paragraphStyle,
      ],
    )
  }

  private func resizeToFit() {
    stack.layoutSubtreeIfNeeded()
    let height = stage == .collapsed
      ? Metrics.collapsedHeight
      : ceil(stack.fittingSize.height) + Metrics.expandedChromeHeight
    // NSMenu ignores intrinsic-size invalidation while tracking; mutating the hosted frame resizes
    // it live, and `menu.update()` is what makes NSMenu re-lay-out the wrapper to the new height.
    // Width is the autoresizing mask's job — the view owning the full native band is what makes
    // ordinary hit testing and one tracking area cover everything a native row covers.
    setFrameSize(NSSize(width: frame.width, height: height))
    needsLayout = true
    layoutSubtreeIfNeeded()
    enclosingMenuItem?.menu?.update()
  }
}
