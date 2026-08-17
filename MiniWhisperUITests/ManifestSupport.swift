import AppKit
import XCTest

/// The accessibility-manifest machinery: a manifest is the complete set of contracts a scene
/// answers to, proven against one snapshot — including that nothing beyond the manifest exists.
extension XCTestCase {
  @MainActor func assertManifest(
    scene: String, audits: Bool = false, elements: [AccessibilityContract],
    mutation: ((XCUIApplication) -> Void)? = nil, file: StaticString = #filePath,
    line: UInt = #line,
  ) throws {
    let app = launch(scene)
    defer { terminate(app) }
    try assertManifest(
      in: app, audits: audits, elements: elements, mutation: mutation, file: file, line: line,
    )
  }

  @MainActor func assertManifest(
    in app: XCUIApplication, audits: Bool = false, elements: [AccessibilityContract],
    mutation: ((XCUIApplication) -> Void)? = nil, file: StaticString = #filePath,
    line: UInt = #line,
  ) throws {
    XCTAssertTrue(
      app.descendants(matching: .any)[elements[0].identifier].awaitExistence(timeout: 5),
      file: file, line: line,
    )
    assert(elements, in: app, allowing: menuKnownIdentifiers, file: file, line: line)
    if audits {
      try app.performAccessibilityAudit(for: [.elementDetection, .action])
    }
    mutation?(app)
  }

  @MainActor func assert(
    _ contracts: [AccessibilityContract], in app: XCUIApplication,
    allowing extraIdentifiers: Set<String> = [], file: StaticString, line: UInt,
  ) {
    let allowedIdentifiers = Set(contracts.map(\.identifier)).union(extraIdentifiers).union([
      "miniwhisper.menu.status-item",
    ])
    var snapshots: [String: [XCUIElementSnapshot]] = [:]
    var snapshotError: Error?
    // The settle condition also demands that nothing beyond the manifest is on screen: after a
    // scene swap, the previous scene's elements are still real until the tree repaints, and
    // waiting only for the new ones would let a stale frame fail the unexpected-identifier claim.
    let settled = poll(timeout: 2) {
      do {
        snapshots = try self.accessibilitySnapshots(app.snapshot())
        return contracts.allSatisfy { contract in
          guard snapshots[contract.identifier]?.count == 1,
                let snapshot = snapshots[contract.identifier]?.first
          else {
            return false
          }
          return contract.value.map { self.accessibilityValue(snapshot) == $0 } ?? true
        } && Set(snapshots.keys).subtracting(allowedIdentifiers).isEmpty
      } catch {
        snapshotError = error
        return false
      }
    }
    if snapshots.isEmpty {
      XCTFail(
        "Could not snapshot the application: \(snapshotError.map(String.init(describing:)) ?? "unknown error")",
        file: file,
        line: line,
      )
      return
    }
    if !settled {
      // Naming the mismatch, because "did not settle" alone sends the reader back to a snapshot
      // they cannot see. Unexpected identifiers are the common cause: a new element reaches the
      // tree and no manifest claims it.
      let unexpected = Set(snapshots.keys).subtracting(allowedIdentifiers).sorted()
      let missing = contracts
        .filter { snapshots[$0.identifier]?.count != 1 }
        .map(\.identifier)
        .sorted()
      let mismatched = contracts.compactMap { contract -> String? in
        guard let snapshot = snapshots[contract.identifier]?.first,
              let expected = contract.value,
              accessibilityValue(snapshot) != expected
        else {
          return nil
        }
        return "\(contract.identifier): expected \(expected), got \(accessibilityValue(snapshot))"
      }
      XCTFail(
        """
        Accessibility tree did not settle
          unexpected: \(unexpected)
          missing or duplicated: \(missing)
          wrong value: \(mismatched)
        """,
        file: file, line: line,
      )
    }

    for contract in contracts {
      let matches = snapshots[contract.identifier, default: []]
      XCTAssertEqual(
        matches.count, 1, "Expected one \(contract.identifier)", file: file, line: line,
      )
      guard let snapshot = matches.first else {
        continue
      }
      XCTAssertEqual(
        snapshot.elementType, contract.elementType, contract.identifier, file: file, line: line,
      )
      XCTAssertFalse(
        snapshot.label.isEmpty, "\(contract.identifier) has no label", file: file, line: line,
      )
      XCTAssertEqual(snapshot.label, contract.label, contract.identifier, file: file, line: line)
      if let value = contract.value {
        XCTAssertEqual(
          accessibilityValue(snapshot), value, contract.identifier, file: file, line: line,
        )
      }
      if let valuePattern = contract.valuePattern {
        XCTAssertNotNil(
          accessibilityValue(snapshot).range(of: valuePattern, options: .regularExpression),
          contract.identifier, file: file, line: line,
        )
      }
      if let isEnabled = contract.isEnabled {
        XCTAssertEqual(snapshot.isEnabled, isEnabled, contract.identifier, file: file, line: line)
      }
      if contract.isActionable {
        let element = app.descendants(matching: .any)[contract.identifier]
        XCTAssertTrue(snapshot.isEnabled, contract.identifier, file: file, line: line)
        XCTAssertTrue(element.isHittable, contract.identifier, file: file, line: line)
      }
    }

    let duplicateIdentifiers = snapshots.filter { $0.value.count > 1 }
    XCTAssertTrue(
      duplicateIdentifiers.isEmpty, "Duplicate identifiers: \(duplicateIdentifiers.keys.sorted())",
      file: file, line: line,
    )

    let unexpectedIdentifiers = Set(snapshots.keys).subtracting(allowedIdentifiers)
    XCTAssertTrue(
      unexpectedIdentifiers.isEmpty, "Unexpected identifiers: \(unexpectedIdentifiers.sorted())",
      file: file, line: line,
    )
  }

  func contract(
    _ elementType: XCUIElement.ElementType, _ identifier: String, _ label: String,
    _ value: String? = nil, valuePattern: String? = nil, isEnabled: Bool? = nil,
    isActionable: Bool = false,
  ) -> AccessibilityContract {
    AccessibilityContract(
      elementType: elementType, identifier: identifier, label: label, value: value,
      valuePattern: valuePattern, isEnabled: isEnabled, isActionable: isActionable,
    )
  }
}

// MARK: - AccessibilityContract

struct AccessibilityContract {
  let elementType: XCUIElement.ElementType
  let identifier: String
  let label: String
  let value: String?
  let valuePattern: String?
  let isEnabled: Bool?
  let isActionable: Bool
}

let menuKnownIdentifiers: Set<String> = [
  "miniwhisper.menu.status", "miniwhisper.menu.repair.accessibility",
  "miniwhisper.menu.repair.microphone", "miniwhisper.menu.copy-last-transcript",
  "miniwhisper.menu.quick-add", "miniwhisper.menu.quick-add.header",
  "miniwhisper.menu.quick-add.word", "miniwhisper.menu.quick-add.disclosure",
  "miniwhisper.menu.quick-add.misspelling", "miniwhisper.menu.quick-add.submit",
  "miniwhisper.menu.quick-add.failure", "miniwhisper.menu.settings",
  "miniwhisper.menu.about", "miniwhisper.menu.quit",
]
