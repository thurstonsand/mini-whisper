import AppKit
import ApplicationServices
import FieldContext
import Foundation
import OSLog

/// Resolves the frontmost application's focused text element and reads a bounded window around
/// its selection.
enum FocusedFieldReader {
  private static let messagingTimeout: Float = 0.020
  private static let captureBudget = Duration.milliseconds(60)
  private static let maximumFocusDepth = 16
  private static let maximumChildWidth = 64

  static func capture() -> ContextCapture {
    let clock = ContinuousClock()
    let started = clock.now
    let capture = Session(deadline: started + captureBudget).read()
    let duration = started.duration(to: clock.now).components
    let elapsed = Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
    contextLogger.info(
      "Context capture \(capture.logDescription, privacy: .public) elapsed=\(elapsed, format: .fixed(precision: 3))ms"
    )
    return capture
  }

  private struct Session {
    let deadline: ContinuousClock.Instant

    private var hasBudget: Bool { ContinuousClock.now < deadline }

    private struct TextTarget {
      var element: AXUIElement
      var role: String
      var characterCount: Int
    }

    func read() -> ContextCapture {
      guard AXIsProcessTrusted() else { return .unavailable(.accessibilityPermissionMissing) }
      guard let frontmost = NSWorkspace.shared.frontmostApplication else {
        return .unavailable(.noFocusedElement)
      }

      let bundleID = frontmost.bundleIdentifier
      guard !TerminalBundleIDs.contains(bundleID) else {
        return .unavailable(.gridSemantics(bundleID: bundleID))
      }

      let application = AXUIElementCreateApplication(frontmost.processIdentifier)
      guard timeoutInstalled(on: application) else {
        return .unavailable(.axFailure(operation: .focusedElement, error: AXError.failure.rawValue))
      }

      let focused: AXUIElement
      switch AXRead.element(application, kAXFocusedUIElementAttribute) {
      case .success(let element): focused = element
      case .failure(let failure):
        return .unavailable(classify(failure, .focusedElement, downgrade: .noFocusedElement))
      }

      switch resolveTextTarget(focused) {
      case .success(let target): return readSlices(from: target)
      case .failure(let reason): return .unavailable(reason)
      }
    }

    /// Chromium hands out a valueless container (`AXWebArea`); the node that owns the value and
    /// the caret is the deepest `AXFocused` descendant. Focus is a chain, so this follows it
    /// rather than searching the tree — a full walk would be expensive
    private func resolveTextTarget(_ focused: AXUIElement) -> Result<TextTarget, ContextUnavailable>
    {
      var element = focused
      var lastRole: String?
      for _ in 0..<maximumFocusDepth {
        guard timeoutInstalled(on: element) else {
          return .failure(.axFailure(operation: .role, error: AXError.failure.rawValue))
        }
        guard hasBudget else { return .failure(.timedOut(operation: .role)) }

        let role: String?
        switch AXRead.string(element, kAXRoleAttribute) {
        case .success(let value): role = value
        case .failure(let failure):
          guard !failure.isTransient else {
            return .failure(classify(failure, .role, downgrade: .nonTextElement(role: lastRole)))
          }
          role = nil
        }
        lastRole = role ?? lastRole

        if let role {
          switch secureness(of: element, role: role) {
          case .secure: return .failure(.protectedField(role: role))
          case .failed(let failure):
            return .failure(classify(failure, .subrole, downgrade: .nonTextElement(role: role)))
          case .plain: break
          }

          if !FieldTargetPolicy.isContainer(role: role) {
            switch AXRead.count(element, kAXNumberOfCharactersAttribute) {
            case .success(let characterCount):
              return .success(
                TextTarget(element: element, role: role, characterCount: characterCount))
            case .failure(let failure):
              guard !failure.isTransient else {
                return .failure(
                  classify(failure, .characterCount, downgrade: .nonTextElement(role: role)))
              }
            }
          }
        }

        switch focusedChild(of: element) {
        case .success(let child?): element = child
        case .success(nil): return .failure(.nonTextElement(role: lastRole))
        case .failure(let reason): return .failure(reason)
        }
      }
      return .failure(.nonTextElement(role: lastRole))
    }

    private func focusedChild(of element: AXUIElement) -> Result<AXUIElement?, ContextUnavailable> {
      let children: [AXUIElement]
      switch AXRead.children(element) {
      case .success(let values): children = values
      case .failure(let failure):
        guard !failure.isTransient else {
          return .failure(classify(failure, .children, downgrade: .nonTextElement(role: nil)))
        }
        return .success(nil)
      }

      for child in children.prefix(maximumChildWidth) {
        guard hasBudget else { return .failure(.timedOut(operation: .children)) }
        guard timeoutInstalled(on: child) else {
          return .failure(.axFailure(operation: .children, error: AXError.failure.rawValue))
        }
        switch AXRead.bool(child, kAXFocusedAttribute) {
        case .success(true): return .success(child)
        case .success(false): continue
        case .failure(let failure):
          // A child that cannot answer is a hung target, not a child to skip past.
          guard !failure.isTransient else {
            return .failure(classify(failure, .children, downgrade: .nonTextElement(role: nil)))
          }
          continue
        }
      }
      return .success(nil)
    }

    private enum Secureness {
      case secure
      case plain
      case failed(AXRead.Failure)
    }

    private func secureness(of element: AXUIElement, role: String) -> Secureness {
      guard !FieldTargetPolicy.isSecure(role: role, subrole: nil) else { return .secure }
      guard FieldTargetPolicy.needsSubroleCheck(role: role) else { return .plain }
      switch AXRead.string(element, kAXSubroleAttribute) {
      case .success(let subrole):
        return FieldTargetPolicy.isSecure(role: role, subrole: subrole) ? .secure : .plain
      case .failure(let failure): return failure.isTransient ? .failed(failure) : .plain
      }
    }

    private func readSlices(from target: TextTarget) -> ContextCapture {
      guard hasBudget else { return .unavailable(.timedOut(operation: .selectedRange)) }

      let selection: CFRange
      switch AXRead.range(target.element, kAXSelectedTextRangeAttribute) {
      case .success(let range): selection = range
      case .failure(let failure):
        return .unavailable(
          classify(failure, .selectedRange, downgrade: .noTextRange(role: target.role)))
      }

      let plan: FocusedTextPlan
      switch FocusedTextPlan.plan(
        characterCount: target.characterCount, selectionLocation: selection.location,
        selectionLength: selection.length)
      {
      case .success(let planned): plan = planned
      case .failure: return .unavailable(.noTextRange(role: target.role))
      }

      var texts = [String]()
      for slice in [plan.before, plan.selected, plan.after] {
        guard slice.length > 0 else {
          texts.append("")
          continue
        }
        guard hasBudget else { return .unavailable(.timedOut(operation: .stringForRange)) }
        switch AXRead.stringForRange(
          target.element, CFRange(location: slice.location, length: slice.length))
        {
        case .success(let text): texts.append(text)
        case .failure(let failure):
          return .unavailable(
            classify(failure, .stringForRange, downgrade: .noTextRange(role: target.role)))
        }
      }

      // A target that answers a bounded range with the wrong text, or hands back half of a
      // surrogate pair, is not serving ranges: a partial capture is unavailable, not best effort.
      switch plan.assemble(role: target.role, before: texts[0], selected: texts[1], after: texts[2])
      {
      case .success(let context): return .available(context)
      case .failure: return .unavailable(.noTextRange(role: target.role))
      }
    }

    private func timeoutInstalled(on element: AXUIElement) -> Bool {
      AXUIElementSetMessagingTimeout(element, messagingTimeout) == .success
    }

    /// Only an explicit "this target does not offer that" downgrades. Timeouts and hung targets
    /// end the capture where they happen, so nothing further is attempted on the delivery path.
    private func classify(
      _ failure: AXRead.Failure, _ operation: ContextAXOperation, downgrade: ContextUnavailable
    ) -> ContextUnavailable {
      switch failure {
      case .ax(.cannotComplete): .timedOut(operation: operation)
      case .ax(let error) where failure.isTransient:
        .axFailure(operation: operation, error: error.rawValue)
      default: downgrade
      }
    }
  }
}

/// Thin `Result`-returning wrappers over the C Accessibility API. This layer decides nothing.
enum AXRead {
  enum Failure: Error, Equatable {
    case ax(AXError)
    case missingValue
    case wrongType

    /// A target that is hung, busy, or refusing to serve the API — as opposed to one that answered
    /// clearly that it does not have what was asked for.
    var isTransient: Bool {
      switch self {
      case .ax(.cannotComplete), .ax(.apiDisabled), .ax(.failure): true
      default: false
      }
    }
  }

  static func value(_ element: AXUIElement, _ attribute: String) -> Result<CFTypeRef, Failure> {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard error == .success else { return .failure(.ax(error)) }
    guard let value else { return .failure(.missingValue) }
    return .success(value)
  }

  static func element(_ element: AXUIElement, _ attribute: String) -> Result<AXUIElement, Failure> {
    value(element, attribute).flatMap { value in
      guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return .failure(.wrongType) }
      return .success(value as! AXUIElement)
    }
  }

  static func string(_ element: AXUIElement, _ attribute: String) -> Result<String, Failure> {
    value(element, attribute).flatMap { value in
      guard let string = value as? String else { return .failure(.wrongType) }
      return .success(string)
    }
  }

  static func count(_ element: AXUIElement, _ attribute: String) -> Result<Int, Failure> {
    value(element, attribute).flatMap { value in
      guard let count = value as? Int else { return .failure(.wrongType) }
      return .success(count)
    }
  }

  static func bool(_ element: AXUIElement, _ attribute: String) -> Result<Bool, Failure> {
    value(element, attribute).flatMap { value in
      guard let flag = value as? Bool else { return .failure(.wrongType) }
      return .success(flag)
    }
  }

  static func range(_ element: AXUIElement, _ attribute: String) -> Result<CFRange, Failure> {
    value(element, attribute).flatMap { value in
      guard CFGetTypeID(value) == AXValueGetTypeID() else { return .failure(.wrongType) }
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
    guard let parameter = AXValueCreate(.cfRange, &requested) else { return .failure(.wrongType) }
    var value: CFTypeRef?
    let error = AXUIElementCopyParameterizedAttributeValue(
      element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &value)
    guard error == .success else { return .failure(.ax(error)) }
    guard let string = value as? String else { return .failure(.wrongType) }
    return .success(string)
  }

  static func children(_ element: AXUIElement) -> Result<[AXUIElement], Failure> {
    value(element, kAXChildrenAttribute).flatMap { value in
      guard let children = value as? [AnyObject] else { return .failure(.wrongType) }
      return .success(
        children.filter { CFGetTypeID($0) == AXUIElementGetTypeID() }.map { $0 as! AXUIElement })
    }
  }
}

extension ContextCapture {
  /// Log-safe description. Field text never appears here at any level — only roles, lengths, and
  /// classifications.
  var logDescription: String {
    switch self {
    case .available(let context):
      "available role=\(context.role) before=\(context.before.utf16.count) selected=\(context.selected.utf16.count) after=\(context.after.utf16.count) truncated=\(context.beforeWasTruncated ? "b" : "-")\(context.selectionWasTruncated ? "s" : "-")\(context.afterWasTruncated ? "a" : "-")"
    case .unavailable(let reason): "unavailable \(reason.logDescription)"
    }
  }
}

extension ContextUnavailable {
  var logDescription: String {
    switch self {
    case .accessibilityPermissionMissing: "accessibilityPermissionMissing"
    case .noFocusedElement: "noFocusedElement"
    case .nonTextElement(let role): "nonTextElement role=\(role ?? "?")"
    case .noTextRange(let role): "noTextRange role=\(role ?? "?")"
    case .gridSemantics(let bundleID): "gridSemantics bundle=\(bundleID ?? "?")"
    case .protectedField(let role): "protectedField role=\(role ?? "?")"
    case .axFailure(let operation, let error):
      "axFailure operation=\(operation.rawValue) ax=\(error)"
    case .timedOut(let operation): "timedOut operation=\(operation.rawValue)"
    }
  }
}
