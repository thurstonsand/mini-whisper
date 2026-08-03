import AppKit
import ApplicationServices
import FieldContext
import Foundation
import OSLog

// MARK: - FocusedFieldReader

/// Resolves the frontmost application's focused text element and reads a bounded window around
/// its selection.
enum FocusedFieldReader {
  // MARK: Internal

  static func capture(source: ContextCaptureSource) -> ContextCapture {
    let clock = ContinuousClock()
    let started = clock.now
    let frontmost = NSWorkspace.shared.frontmostApplication
    let capture = Session(deadline: started + captureBudget).read(frontmost: frontmost)
    let duration = started.duration(to: clock.now).components
    let elapsed = Double(duration.seconds) * 1000 + Double(duration.attoseconds) / 1e15
    contextLogger.info(
      "Context capture source=\(source.rawValue, privacy: .public) \(capture.logDescription, privacy: .public) pid=\(frontmost?.processIdentifier ?? -1) elapsed=\(elapsed, format: .fixed(precision: 3))ms",
    )
    return capture
  }

  // MARK: Private

  private struct Session {
    // MARK: Internal

    let deadline: ContinuousClock.Instant

    func read(frontmost: NSRunningApplication?) -> ContextCapture {
      guard AXIsProcessTrusted() else {
        return .unavailable(.accessibilityPermissionMissing)
      }
      guard let frontmost else {
        return .unavailable(.noFocusedElement)
      }

      let bundleID = frontmost.bundleIdentifier
      guard !TerminalBundleIDs.contains(bundleID) else {
        return .unavailable(.gridSemantics(bundleID: bundleID))
      }

      let application = AXUIElementCreateApplication(frontmost.processIdentifier)
      if let blocked = arm(application, cap: firstContactTimeout, for: .focusedElement) {
        return .unavailable(blocked)
      }

      let focused: AXUIElement
      switch AXRead.element(application, kAXFocusedUIElementAttribute) {
      case let .success(element):
        focused = element
      case let .failure(failure):
        return .unavailable(classify(failure, .focusedElement, downgrade: .noFocusedElement))
      }

      switch resolveTextTarget(focused) {
      case let .success(target):
        return readSlices(from: target)
      case let .failure(reason):
        return .unavailable(reason)
      }
    }

    // MARK: Private

    private struct TextTarget {
      var element: AXUIElement
      var role: String
      var characterCount: Int
    }

    private enum Secureness {
      case secure
      case plain
      case blocked(ContextUnavailable)
    }

    /// Chromium hands out a valueless container (`AXWebArea`); the node that owns the value and
    /// the caret is the deepest `AXFocused` descendant. Focus is a chain, so this follows it
    /// rather than searching the tree — a full walk would be expensive
    private func resolveTextTarget(_ focused: AXUIElement) -> Result<TextTarget, ContextUnavailable>
    {
      var element = focused
      var lastRole: String?
      for _ in 0 ..< maximumFocusDepth {
        if let blocked = arm(element, for: .role) {
          return .failure(blocked)
        }

        let role: String?
        switch AXRead.string(element, kAXRoleAttribute) {
        case let .success(value):
          role = value
        case let .failure(failure):
          guard !failure.isTransient else {
            return .failure(classify(failure, .role, downgrade: .nonTextElement(role: lastRole)))
          }
          role = nil
        }
        lastRole = role ?? lastRole

        if let role {
          switch secureness(of: element, role: role) {
          case .secure:
            return .failure(.protectedField(role: role))
          case let .blocked(reason):
            return .failure(reason)
          case .plain:
            break
          }

          if !FieldTargetPolicy.isContainer(role: role) {
            if let blocked = arm(element, for: .characterCount) {
              return .failure(blocked)
            }
            switch AXRead.count(element, kAXNumberOfCharactersAttribute) {
            case let .success(characterCount):
              return .success(
                TextTarget(element: element, role: role, characterCount: characterCount),
              )
            case let .failure(failure):
              guard !failure.isTransient else {
                return .failure(
                  classify(failure, .characterCount, downgrade: .nonTextElement(role: role)),
                )
              }
            }
          }
        }

        switch focusedChild(of: element) {
        case let .success(child?):
          element = child
        case .success(nil):
          return .failure(.nonTextElement(role: lastRole))
        case let .failure(reason):
          return .failure(reason)
        }
      }
      return .failure(.nonTextElement(role: lastRole))
    }

    private func focusedChild(of element: AXUIElement) -> Result<AXUIElement?, ContextUnavailable> {
      if let blocked = arm(element, for: .children) {
        return .failure(blocked)
      }

      let children: [AXUIElement]
      switch AXRead.children(element) {
      case let .success(values):
        children = values
      case let .failure(failure):
        guard !failure.isTransient else {
          return .failure(classify(failure, .children, downgrade: .nonTextElement(role: nil)))
        }
        return .success(nil)
      }

      for child in children.prefix(maximumChildWidth) {
        if let blocked = arm(child, for: .children) {
          return .failure(blocked)
        }
        switch AXRead.bool(child, kAXFocusedAttribute) {
        case .success(true):
          return .success(child)
        case .success(false):
          continue
        case let .failure(failure):
          // A child that cannot answer is a hung target, not a child to skip past.
          guard !failure.isTransient else {
            return .failure(classify(failure, .children, downgrade: .nonTextElement(role: nil)))
          }
          continue
        }
      }
      return .success(nil)
    }

    private func secureness(of element: AXUIElement, role: String) -> Secureness {
      guard !FieldTargetPolicy.isSecure(role: role, subrole: nil) else {
        return .secure
      }
      guard FieldTargetPolicy.needsSubroleCheck(role: role) else {
        return .plain
      }
      if let blocked = arm(element, for: .subrole) {
        return .blocked(blocked)
      }
      switch AXRead.string(element, kAXSubroleAttribute) {
      case let .success(subrole):
        return FieldTargetPolicy.isSecure(role: role, subrole: subrole) ? .secure : .plain
      case let .failure(failure):
        return failure.isTransient
          ? .blocked(classify(failure, .subrole, downgrade: .nonTextElement(role: role))) : .plain
      }
    }

    private func readSlices(from target: TextTarget) -> ContextCapture {
      if let blocked = arm(target.element, for: .selectedRange) {
        return .unavailable(blocked)
      }

      let selection: CFRange
      switch AXRead.range(target.element, kAXSelectedTextRangeAttribute) {
      case let .success(range):
        selection = range
      case let .failure(failure):
        return .unavailable(
          classify(failure, .selectedRange, downgrade: .noTextRange(role: target.role)),
        )
      }

      let plan: FocusedTextPlan
      switch FocusedTextPlan.plan(
        characterCount: target.characterCount, selectionLocation: selection.location,
        selectionLength: selection.length,
      ) {
      case let .success(planned):
        plan = planned
      case .failure:
        return .unavailable(.noTextRange(role: target.role))
      }

      var texts = [String]()
      for slice in [plan.before, plan.selected, plan.after] {
        guard slice.length > 0 else {
          texts.append("")
          continue
        }
        if let blocked = arm(target.element, for: .stringForRange) {
          return .unavailable(blocked)
        }
        switch AXRead.stringForRange(
          target.element, CFRange(location: slice.location, length: slice.length),
        ) {
        case let .success(text):
          texts.append(text)
        case let .failure(failure):
          return .unavailable(
            classify(failure, .stringForRange, downgrade: .noTextRange(role: target.role)),
          )
        }
      }

      // A target that answers a bounded range with the wrong text, or hands back half of a
      // surrogate pair, is not serving ranges: a partial capture is unavailable, not best effort.
      switch plan.assemble(role: target.role, before: texts[0], selected: texts[1], after: texts[2])
      {
      case let .success(context):
        return context.isZeroWidthSink
          ? .unavailable(.zeroWidthSink(role: target.role)) : .available(context)
      case .failure:
        return .unavailable(.noTextRange(role: target.role))
      }
    }

    /// Every AX request is bounded twice: by its own cap and by whatever is left of the capture
    /// budget. The Accessibility API offers no whole-capture deadline, so the budget is enforced
    /// the only way it can be — by shrinking each individual request's messaging timeout to fit
    /// inside it. A request that would start with nothing left never starts.
    private func arm(
      _ element: AXUIElement, cap: Float = messagingTimeout, for operation: ContextAXOperation,
    ) -> ContextUnavailable? {
      let remaining = ContinuousClock.now.duration(to: deadline).components
      let seconds =
        Float(remaining.seconds) + Float(remaining.attoseconds) / 1e18
      guard seconds > 0 else {
        return .timedOut(operation: operation)
      }
      guard AXUIElementSetMessagingTimeout(element, min(cap, seconds)) == .success else {
        return .axFailure(operation: operation, error: AXError.failure.rawValue)
      }
      return nil
    }

    /// Only an explicit "this target does not offer that" downgrades. Timeouts and hung targets
    /// end the capture where they happen, so nothing further is attempted on the delivery path.
    private func classify(
      _ failure: AXRead.Failure, _ operation: ContextAXOperation, downgrade: ContextUnavailable,
    ) -> ContextUnavailable {
      switch failure {
      case .ax(.cannotComplete):
        .timedOut(operation: operation)
      case let .ax(error) where failure.isTransient:
        .axFailure(operation: operation, error: error.rawValue)
      default:
        downgrade
      }
    }
  }

  private static let messagingTimeout: Float = 0.020
  /// The first message to an application this process has not spoken to yet costs the connection
  /// itself: measured 8–20 ms against a running Dia and up to 17 ms against Chrome, while every
  /// read that follows it is sub-millisecond. A 20 ms cap sits inside that distribution, so the
  /// handshake gets its own, wider one; the budget still bounds it, because every request is
  /// installed at no more than the time remaining.
  private static let firstContactTimeout: Float = 0.040
  private static let captureBudget = Duration.milliseconds(60)
  private static let maximumFocusDepth = 16
  private static let maximumChildWidth = 64
}

// MARK: - AXRead

/// Thin `Result`-returning wrappers over the C Accessibility API. This layer decides nothing.
enum AXRead {
  enum Failure: Error, Equatable {
    case ax(AXError)
    case missingValue
    case wrongType

    // MARK: Internal

    /// A target that is hung, busy, or refusing to serve the API — as opposed to one that answered
    /// clearly that it does not have what was asked for.
    var isTransient: Bool {
      switch self {
      case .ax(.cannotComplete),
           .ax(.apiDisabled),
           .ax(.failure):
        true
      default:
        false
      }
    }
  }

  static func value(_ element: AXUIElement, _ attribute: String) -> Result<CFTypeRef, Failure> {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard error == .success else {
      return .failure(.ax(error))
    }
    guard let value else {
      return .failure(.missingValue)
    }
    return .success(value)
  }

  static func element(_ element: AXUIElement, _ attribute: String) -> Result<AXUIElement, Failure> {
    value(element, attribute).flatMap { value in
      guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
        return .failure(.wrongType)
      }
      return .success(value as! AXUIElement)
    }
  }

  static func string(_ element: AXUIElement, _ attribute: String) -> Result<String, Failure> {
    value(element, attribute).flatMap { value in
      guard let string = value as? String else {
        return .failure(.wrongType)
      }
      return .success(string)
    }
  }

  static func count(_ element: AXUIElement, _ attribute: String) -> Result<Int, Failure> {
    value(element, attribute).flatMap { value in
      guard let count = value as? Int else {
        return .failure(.wrongType)
      }
      return .success(count)
    }
  }

  static func bool(_ element: AXUIElement, _ attribute: String) -> Result<Bool, Failure> {
    value(element, attribute).flatMap { value in
      guard let flag = value as? Bool else {
        return .failure(.wrongType)
      }
      return .success(flag)
    }
  }

  static func range(_ element: AXUIElement, _ attribute: String) -> Result<CFRange, Failure> {
    value(element, attribute).flatMap { value in
      guard CFGetTypeID(value) == AXValueGetTypeID() else {
        return .failure(.wrongType)
      }
      var range = CFRange()
      let axValue = value as! AXValue
      guard AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range) else {
        return .failure(.wrongType)
      }
      return .success(range)
    }
  }

  static func stringForRange(_ element: AXUIElement, _ range: CFRange) -> Result<String, Failure> {
    var requested = range
    guard let parameter = AXValueCreate(.cfRange, &requested) else {
      return .failure(.wrongType)
    }
    var value: CFTypeRef?
    let error = AXUIElementCopyParameterizedAttributeValue(
      element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &value,
    )
    guard error == .success else {
      return .failure(.ax(error))
    }
    guard let string = value as? String else {
      return .failure(.wrongType)
    }
    return .success(string)
  }

  static func children(_ element: AXUIElement) -> Result<[AXUIElement], Failure> {
    value(element, kAXChildrenAttribute).flatMap { value in
      guard let children = value as? [AnyObject] else {
        return .failure(.wrongType)
      }
      return .success(
        children.filter { CFGetTypeID($0) == AXUIElementGetTypeID() }.map { $0 as! AXUIElement },
      )
    }
  }
}

extension ContextCapture {
  /// Log-safe description. Field text never appears here at any level — only roles, lengths, and
  /// classifications.
  var logDescription: String {
    switch self {
    case let .available(context):
      "available role=\(context.role) before=\(context.before.utf16.count) selected=\(context.selected.utf16.count) after=\(context.after.utf16.count) truncated=\(context.beforeWasTruncated ? "b" : "-")\(context.selectionWasTruncated ? "s" : "-")\(context.afterWasTruncated ? "a" : "-")"
    case let .unavailable(reason):
      "unavailable \(reason.logDescription)"
    }
  }
}

extension ContextUnavailable {
  var logDescription: String {
    switch self {
    case .accessibilityPermissionMissing:
      "accessibilityPermissionMissing"
    case .noFocusedElement:
      "noFocusedElement"
    case let .nonTextElement(role):
      "nonTextElement role=\(role ?? "?")"
    case let .noTextRange(role):
      "noTextRange role=\(role ?? "?")"
    case let .gridSemantics(bundleID):
      "gridSemantics bundle=\(bundleID ?? "?")"
    case let .zeroWidthSink(role):
      "zeroWidthSink role=\(role ?? "?")"
    case let .protectedField(role):
      "protectedField role=\(role ?? "?")"
    case let .axFailure(operation, error):
      "axFailure operation=\(operation.rawValue) ax=\(error)"
    case let .timedOut(operation):
      "timedOut operation=\(operation.rawValue)"
    }
  }
}
