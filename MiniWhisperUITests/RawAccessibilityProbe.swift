import ApplicationServices
import Foundation

struct RawAccessibilitySnapshot {
  let role: String
  let identifier: String
  let label: String
  let value: String
}

struct RawAccessibilityFailure {
  let attribute: String
  let error: AXError
}

enum RawAccessibilityResult {
  case snapshot(RawAccessibilitySnapshot)
  case failure(RawAccessibilityFailure)
  case notFound
}

struct RawAccessibilityProbe {
  func read(applicationPID: pid_t, identifier: String) -> RawAccessibilityResult {
    let application = AXUIElementCreateApplication(applicationPID)
    var pending = [application]
    pending.append(contentsOf: elements(application, attribute: kAXWindowsAttribute).elements)
    var firstFailure: RawAccessibilityFailure?
    var visited: Set<CFHashCode> = []

    while let element = pending.popLast() {
      guard visited.insert(CFHash(element)).inserted else { continue }
      let identifierResult = string(element, attribute: kAXIdentifierAttribute)
      if identifierResult.value == identifier {
        return .snapshot(
          RawAccessibilitySnapshot(
            role: string(element, attribute: kAXRoleAttribute).value,
            identifier: identifierResult.value,
            label: string(element, attribute: kAXDescriptionAttribute).value,
            value: string(element, attribute: kAXValueAttribute).value))
      }
      if firstFailure == nil, let failure = identifierResult.failure, failure.error != .noValue,
        failure.error != .attributeUnsupported
      {
        firstFailure = failure
      }

      let childResult = elements(element, attribute: kAXChildrenAttribute)
      pending.append(contentsOf: childResult.elements)
      if firstFailure == nil, let failure = childResult.failure { firstFailure = failure }
    }

    if let firstFailure { return .failure(firstFailure) }
    return .notFound
  }

  private func string(
    _ element: AXUIElement, attribute: String
  ) -> (value: String, failure: RawAccessibilityFailure?) {
    var rawValue: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &rawValue)
    guard error == .success, let rawValue else {
      return ("", RawAccessibilityFailure(attribute: attribute, error: error))
    }
    return (String(describing: rawValue), nil)
  }

  private func elements(
    _ element: AXUIElement, attribute: String
  ) -> (elements: [AXUIElement], failure: RawAccessibilityFailure?) {
    var rawValue: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &rawValue)
    guard error == .success, let rawValue else {
      if error == .noValue || error == .attributeUnsupported { return ([], nil) }
      return ([], RawAccessibilityFailure(attribute: attribute, error: error))
    }
    guard CFGetTypeID(rawValue) == CFArrayGetTypeID() else {
      return ([], RawAccessibilityFailure(attribute: attribute, error: .illegalArgument))
    }

    let array = unsafeBitCast(rawValue, to: CFArray.self)
    let elements = (0..<CFArrayGetCount(array)).map { index in
      unsafeBitCast(CFArrayGetValueAtIndex(array, index), to: AXUIElement.self)
    }
    return (elements, nil)
  }
}
