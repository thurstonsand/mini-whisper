import SwiftUI

// MARK: - AudioLevelBars

struct AudioLevelBars: View {
  // MARK: Internal

  var level: Float

  var body: some View {
    HStack(spacing: 2.5) {
      ForEach(maximumHeights.indices, id: \.self) { index in
        Capsule().fill(.primary.opacity(0.78)).frame(
          width: 2.5, height: barHeight(maximum: maximumHeights[index], index: index),
        )
      }
    }
    .frame(width: 22.5, height: 20)
    .animation(.linear(duration: 0.08), value: level)
  }

  // MARK: Private

  private let maximumHeights: [CGFloat] = [8, 14, 19, 14, 8]

  private func barHeight(maximum: CGFloat, index: Int) -> CGFloat {
    let variation: Float = index.isMultiple(of: 2) ? 0.82 : 1
    return max(3, maximum * CGFloat(min(level * 1.35 * variation, 1)))
  }
}
