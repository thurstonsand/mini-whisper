import SwiftUI

// MARK: - SemanticText

struct SemanticText: View {
  // MARK: Lifecycle

  init(_ text: String, identifier: String, label: String, value: String? = nil) {
    self.text = text
    self.identifier = identifier
    self.label = label
    self.value = value ?? text
  }

  // MARK: Internal

  var body: some View {
    Text(text).accessibilityIdentifier(identifier).accessibilityLabel(label).accessibilityValue(
      value,
    )
  }

  // MARK: Private

  private let text: String
  private let identifier: String
  private let label: String
  private let value: String
}

extension View {
  /// Reports paint that lives in a background, an overlay, or a fill — none of which own an
  /// accessible element — by pinning an invisible `SemanticText` over the thing being painted.
  /// The value must come from the same derivation that drives the paint, or it describes fiction.
  func accessibilityPaintState(
    _ identifier: String, label: String, value: String,
  ) -> some View {
    overlay(alignment: .topLeading) {
      SemanticText(label, identifier: identifier, label: label, value: value)
        .foregroundStyle(.clear)
        .frame(width: 1, height: 1)
        .allowsHitTesting(false)
    }
  }
}
