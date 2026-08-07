import SwiftUI

// MARK: - HotkeyKeycaps

struct HotkeyKeycaps: View {
  let components: [String]
  var scale: CGFloat = 1
  var ringed = false

  var body: some View {
    HStack(spacing: 3 * scale) {
      ForEach(Array(components.enumerated()), id: \.offset) { _, component in
        Text(component)
          .font(.system(size: 12 * scale))
          .padding(.horizontal, 7 * scale)
          .padding(.vertical, 3 * scale)
          .background {
            RoundedRectangle(cornerRadius: 5 * scale).fill(.quaternary)
          }
      }
    }
    .padding(3 * scale)
    .background {
      RoundedRectangle(cornerRadius: 7 * scale).fill(.quinary)
    }
    .overlay {
      RoundedRectangle(cornerRadius: 7 * scale)
        .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
        .opacity(ringed ? 1 : 0)
    }
  }
}
