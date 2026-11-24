import AppKit
import CoreGraphics

/// Draws MiniWhisper's 18 pt menu bar icon: Polly's silhouette, a bottom-right monochrome channel
/// mark (`☾` for Nightly, `{}` for Dev, none for Release), and — only while degraded — a top-left
/// `.systemOrange` badge naming the highest-priority failure without covering the channel mark.
enum MenuBarIcon {
  // MARK: Internal

  enum DegradedCategory: Equatable, CaseIterable {
    case permissions
    case model
    case credential
    case error

    // MARK: Lifecycle

    init?(degradation: Degradation?) {
      guard let degradation else {
        return nil
      }
      switch degradation {
      case .accessibilityDenied,
           .microphoneAccessDenied:
        self = .permissions
      case .modelMissing,
           .gateMissing,
           .modelSetupFailed:
        self = .model
      case .engineKeyMissing,
           .cleanupKeyMissing:
        self = .credential
      case .hotkeyTapDead,
           .settingsFileUnreadable,
           .historyFileUnreadable:
        self = .error
      }
    }

    // MARK: Internal

    var accessibilitySuffix: String {
      switch self {
      case .permissions:
        "permissions needed"
      case .model:
        "model setup needed"
      case .credential:
        "API key needed"
      case .error:
        "attention needed"
      }
    }

    var symbolName: String {
      switch self {
      case .permissions:
        "lock.fill"
      case .model:
        "arrow.down"
      case .credential:
        "key.fill"
      case .error:
        "exclamationmark.triangle.fill"
      }
    }

    var symbolPointSize: CGFloat {
      switch self {
      case .model:
        8.2
      case .permissions,
           .credential:
        8.5
      case .error:
        8.6
      }
    }

    var symbolWeight: NSFont.Weight {
      switch self {
      case .model:
        .bold
      case .permissions,
           .credential,
           .error:
        .semibold
      }
    }

    var usesInnerWhiteGlyph: Bool {
      self == .error
    }
  }

  struct Descriptor: Equatable {
    let channel: Channel.Kind
    let degraded: DegradedCategory?
  }

  static let iconSize = CGSize(width: 18, height: 18)

  static func image(for descriptor: Descriptor,
                    accessibilityName: String = Channel.name) -> NSImage
  {
    let image = NSImage(size: iconSize, flipped: false) { rect in
      guard let ctx = NSGraphicsContext.current?.cgContext else {
        return false
      }
      draw(descriptor, in: rect, context: ctx)
      return true
    }
    // Healthy icons are pure template alpha masks so AppKit owns light/dark, wallpaper vibrancy,
    // and inactive-display dimming. Degraded icons resolve `NSColor.labelColor` live inside the
    // drawing handler so the parrot still tracks appearance while the badge keeps `.systemOrange`.
    image.isTemplate = descriptor.degraded == nil
    if let degraded = descriptor.degraded {
      image.accessibilityDescription = "\(accessibilityName), \(degraded.accessibilitySuffix)"
    } else {
      image.accessibilityDescription = accessibilityName
    }
    return image
  }

  // MARK: Private

  /// Polly's head/bust silhouette traced from `AppIcon.icon/Assets/2-parrot.png` into a 0...100
  /// Y-down coordinate space: rounded crown, 3-feather crest, hooked open beak, and smooth bust.
  private static func makeParrotBodyPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 27, y: 15))
    path.addCurve(
      to: CGPoint(x: 66, y: 12), control1: CGPoint(x: 38, y: 3), control2: CGPoint(x: 56, y: 4),
    )
    // Top crest feather
    path.addCurve(
      to: CGPoint(x: 91, y: 11), control1: CGPoint(x: 76, y: 14), control2: CGPoint(x: 86, y: 13),
    )
    path.addCurve(
      to: CGPoint(x: 73, y: 25), control1: CGPoint(x: 88, y: 20), control2: CGPoint(x: 80, y: 24),
    )
    // Middle crest feather
    path.addCurve(
      to: CGPoint(x: 97, y: 32), control1: CGPoint(x: 83, y: 28), control2: CGPoint(x: 92, y: 31),
    )
    path.addCurve(
      to: CGPoint(x: 81, y: 41), control1: CGPoint(x: 93, y: 40), control2: CGPoint(x: 87, y: 42),
    )
    // Lower crest feather
    path.addCurve(
      to: CGPoint(x: 94, y: 51), control1: CGPoint(x: 88, y: 46), control2: CGPoint(x: 92, y: 49),
    )
    path.addCurve(
      to: CGPoint(x: 80, y: 58), control1: CGPoint(x: 90, y: 58), control2: CGPoint(x: 84, y: 59),
    )
    // Smooth bust base curving continuously into the lower beak underside
    path.addCurve(
      to: CGPoint(x: 85, y: 76), control1: CGPoint(x: 84, y: 64), control2: CGPoint(x: 86, y: 70),
    )
    path.addCurve(
      to: CGPoint(x: 42, y: 90), control1: CGPoint(x: 81, y: 89), control2: CGPoint(x: 62, y: 94),
    )
    path.addCurve(
      to: CGPoint(x: 11, y: 65), control1: CGPoint(x: 27, y: 87), control2: CGPoint(x: 17, y: 76),
    )
    // Open mouth cavity and hooked upper beak
    path.addCurve(
      to: CGPoint(x: 36, y: 55), control1: CGPoint(x: 20, y: 66), control2: CGPoint(x: 30, y: 62),
    )
    path.addCurve(
      to: CGPoint(x: 35, y: 41), control1: CGPoint(x: 39, y: 50), control2: CGPoint(x: 38, y: 44),
    )
    path.addCurve(
      to: CGPoint(x: 8, y: 51), control1: CGPoint(x: 24, y: 37), control2: CGPoint(x: 13, y: 41),
    )
    path.addCurve(
      to: CGPoint(x: 27, y: 15), control1: CGPoint(x: 1, y: 38), control2: CGPoint(x: 8, y: 17),
    )
    path.closeSubpath()
    return path
  }

  private static func makeParrotEyeCutoutPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 41.5, y: 32.5))
    path.addQuadCurve(to: CGPoint(x: 65.5, y: 26), control: CGPoint(x: 53.5, y: 27.5))
    path.addCurve(
      to: CGPoint(x: 53.5, y: 50), control1: CGPoint(x: 69, y: 37.5), control2: CGPoint(
        x: 63,
        y: 50,
      ),
    )
    path.addCurve(
      to: CGPoint(x: 41.5, y: 32.5),
      control1: CGPoint(x: 43, y: 50),
      control2: CGPoint(x: 39, y: 40.5),
    )
    path.closeSubpath()
    return path
  }

  private static func makeParrotPupilPath() -> CGPath {
    CGPath(ellipseIn: CGRect(x: 44.5, y: 33.5, width: 11, height: 11), transform: nil)
  }

  private static func draw(_ descriptor: Descriptor, in rect: CGRect, context ctx: CGContext) {
    let inset = rect.insetBy(dx: 0.5, dy: 0.5)
    let ink: NSColor = descriptor.degraded == nil ? .black : .labelColor
    let degradedSymbol = descriptor.degraded.flatMap { makeDegradedSymbol($0) }
    let degradedRect = degradedSymbol.map { symbol -> CGRect in
      let size = symbol.size
      return CGRect(
        x: inset.minX - 0.5,
        y: inset.maxY - size.height + 0.5,
        width: size.width,
        height: size.height,
      )
    }

    // Isolate `.clear` and `.destinationOut` knockouts inside a transparency layer so they only cut
    // through Polly and never erase the translucent menu bar surface underneath.
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    drawNormalized(in: ctx, rect: inset) { c in
      c.setFillColor(ink.cgColor)
      c.addPath(makeParrotBodyPath())
      c.fillPath()

      c.saveGState()
      c.setBlendMode(.clear)
      c.addPath(makeParrotEyeCutoutPath())
      c.fillPath()
      c.restoreGState()

      c.setFillColor(ink.cgColor)
      c.addPath(makeParrotPupilPath())
      c.fillPath()
    }

    drawChannelMark(descriptor.channel, in: ctx, rect: inset, ink: ink)

    if let symbol = degradedSymbol, let symRect = degradedRect {
      // Contour-hugging transparent halo around the exact SF Symbol silhouette.
      let haloRadius: CGFloat = 1.25
      let steps = 12
      for i in 0 ..< steps {
        let angle = (CGFloat(i) / CGFloat(steps)) * .pi * 2
        let offset = symRect.offsetBy(dx: cos(angle) * haloRadius, dy: sin(angle) * haloRadius)
        symbol.draw(in: offset, from: .zero, operation: .destinationOut, fraction: 1.0)
      }
      symbol.draw(in: symRect, from: .zero, operation: .destinationOut, fraction: 1.0)
    }
    ctx.endTransparencyLayer()

    if let symbol = degradedSymbol, let symRect = degradedRect {
      symbol.draw(in: symRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }
  }

  private static func drawChannelMark(
    _ channel: Channel.Kind, in ctx: CGContext, rect: CGRect, ink: NSColor,
  ) {
    switch channel {
    case .release:
      break

    case .nightly:
      let cx: CGFloat = 80
      let cy: CGFloat = 80
      let outerR: CGFloat = 21.5
      let moonR: CGFloat = 16
      drawNormalized(in: ctx, rect: rect) { c in
        c.saveGState()
        c.setBlendMode(.clear)
        c.addEllipse(
          in: CGRect(x: cx - outerR, y: cy - outerR, width: outerR * 2, height: outerR * 2),
        )
        c.fillPath()
        c.restoreGState()

        c.setFillColor(ink.cgColor)
        c.addEllipse(in: CGRect(x: cx - moonR, y: cy - moonR, width: moonR * 2, height: moonR * 2))
        c.fillPath()

        c.saveGState()
        c.setBlendMode(.clear)
        c.addEllipse(
          in: CGRect(
            x: cx - moonR + 7.5, y: cy - moonR - 3.5, width: moonR * 1.75, height: moonR * 1.75,
          ),
        )
        c.fillPath()
        c.restoreGState()
      }

    case .dev:
      drawNormalized(in: ctx, rect: rect) { c in
        c.saveGState()
        c.setBlendMode(.clear)
        let halo = CGPath(
          roundedRect: CGRect(x: 50, y: 56, width: 52, height: 46),
          cornerWidth: 13, cornerHeight: 13, transform: nil,
        )
        c.addPath(halo)
        c.fillPath()
        c.restoreGState()

        c.setStrokeColor(ink.cgColor)
        c.setLineWidth(8.2)
        c.setLineCap(.round)
        c.setLineJoin(.round)
        // Left curly brace `{`
        c.move(to: CGPoint(x: 70, y: 63))
        c.addQuadCurve(to: CGPoint(x: 64, y: 71), control: CGPoint(x: 64, y: 63))
        c.addLine(to: CGPoint(x: 64, y: 75))
        c.addLine(to: CGPoint(x: 58, y: 79.5))
        c.addLine(to: CGPoint(x: 64, y: 84))
        c.addLine(to: CGPoint(x: 64, y: 88))
        c.addQuadCurve(to: CGPoint(x: 70, y: 96), control: CGPoint(x: 64, y: 96))
        // Right curly brace `}`
        c.move(to: CGPoint(x: 84, y: 63))
        c.addQuadCurve(to: CGPoint(x: 90, y: 71), control: CGPoint(x: 90, y: 63))
        c.addLine(to: CGPoint(x: 90, y: 75))
        c.addLine(to: CGPoint(x: 96, y: 79.5))
        c.addLine(to: CGPoint(x: 90, y: 84))
        c.addLine(to: CGPoint(x: 90, y: 88))
        c.addQuadCurve(to: CGPoint(x: 84, y: 96), control: CGPoint(x: 90, y: 96))
        c.strokePath()
      }
    }
  }

  private static func makeDegradedSymbol(_ category: DegradedCategory) -> NSImage? {
    let palette: [NSColor] = category
      .usesInnerWhiteGlyph ? [.white, .systemOrange] : [.systemOrange]
    let config = NSImage.SymbolConfiguration(
      pointSize: category.symbolPointSize, weight: category.symbolWeight,
    )
    .applying(.init(paletteColors: palette))
    guard let image = NSImage(
      systemSymbolName: category.symbolName, accessibilityDescription: nil,
    )?.withSymbolConfiguration(config)
    else {
      return nil
    }
    image.isTemplate = false
    return image
  }

  private static func drawNormalized(
    in ctx: CGContext, rect: CGRect, draw: (CGContext) -> Void,
  ) {
    ctx.saveGState()
    ctx.translateBy(x: rect.minX, y: rect.maxY)
    ctx.scaleBy(x: rect.width / 100, y: -rect.height / 100)
    draw(ctx)
    ctx.restoreGState()
  }
}
