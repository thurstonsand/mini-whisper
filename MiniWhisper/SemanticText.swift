import SwiftUI

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
