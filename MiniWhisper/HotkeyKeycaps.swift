import SwiftUI

// MARK: - HotkeyKeycaps

struct HotkeyKeycaps: View {
  let components: [String]
  var ringed = false

  var body: some View {
    HStack(spacing: 3) {
      ForEach(Array(components.enumerated()), id: \.offset) { _, component in
        Text(component)
          .font(.callout)
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .background {
            RoundedRectangle(cornerRadius: 5).fill(.quaternary)
          }
      }
    }
    .padding(3)
    .background {
      RoundedRectangle(cornerRadius: 7).fill(.quinary)
    }
    .overlay {
      RoundedRectangle(cornerRadius: 7)
        .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
        .opacity(ringed ? 1 : 0)
    }
  }
}
