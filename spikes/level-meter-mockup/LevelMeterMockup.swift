// Disposable design spike: live microphone level meter treatments for the settings pane's
// Microphone row. Six variants, all driven by the real default input with NO smoothing on the
// capture side, so liveness can be judged honestly. Run, hum, compare.
//
//   swiftc -framework AppKit -framework SwiftUI -framework AVFAudio \
//     spikes/level-meter-mockup/LevelMeterMockup.swift -o .build/level-meter-mockup
//   .build/level-meter-mockup [light|dark]

import AppKit
import AVFAudio
import SwiftUI

// MARK: - Live capture

final class LiveLevel: ObservableObject {
  // Raw instantaneous values, published per tap buffer (~21ms at 48k/1024).
  @Published var rms: Float = 0
  @Published var peak: Float = 0
  // Rolling history for waveform variants; newest last.
  @Published var history: [Float] = Array(repeating: 0, count: 48)

  private let engine = AVAudioEngine()

  func start() {
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
      guard let self, let data = buffer.floatChannelData?[0] else { return }
      let frames = Int(buffer.frameLength)
      var sum: Float = 0
      var peak: Float = 0
      for i in 0 ..< frames {
        let sample = data[i]
        sum += sample * sample
        peak = max(peak, abs(sample))
      }
      let rms = sqrt(sum / Float(max(frames, 1)))
      DispatchQueue.main.async {
        self.rms = rms
        self.peak = peak
        self.history.removeFirst()
        self.history.append(rms)
      }
    }
    engine.prepare()
    try? engine.start()
  }
}

// Map linear amplitude to a 0...1 display value the way audio gear does: dB with a floor.
func meterValue(_ amplitude: Float) -> Double {
  guard amplitude > 0 else { return 0 }
  let db = 20 * log10(amplitude)
  let floor: Float = -55
  return Double(max(0, min(1, (db - floor) / -floor)))
}

// MARK: - Variants

struct ThermometerMeter: View {
  @ObservedObject var level: LiveLevel
  @State private var peakHold: Double = 0
  @State private var peakDecayTask: Task<Void, Never>?

  var body: some View {
    let value = meterValue(level.rms)
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule().fill(.quaternary)
        Capsule()
          .fill(Color.accentColor)
          .frame(width: max(4, geo.size.width * value))
        // Peak-hold tick, decaying.
        Capsule()
          .fill(.primary.opacity(0.55))
          .frame(width: 2, height: geo.size.height)
          .offset(x: geo.size.width * peakHold - 1)
      }
    }
    .frame(width: 72, height: 6)
    .onChange(of: level.peak) { _, newPeak in
      let v = meterValue(newPeak)
      if v > peakHold {
        peakHold = v
        peakDecayTask?.cancel()
        peakDecayTask = Task { @MainActor in
          try? await Task.sleep(for: .milliseconds(700))
          guard !Task.isCancelled else { return }
          withAnimation(.easeOut(duration: 0.5)) { peakHold = 0 }
        }
      }
    }
  }
}

struct SegmentedMeter: View {
  @ObservedObject var level: LiveLevel

  var body: some View {
    let value = meterValue(level.rms)
    HStack(spacing: 2) {
      ForEach(0 ..< 14, id: \.self) { index in
        let threshold = Double(index) / 14
        let lit = value > threshold
        RoundedRectangle(cornerRadius: 1)
          .fill(color(for: index).opacity(lit ? 1 : 0.18))
          .frame(width: 3, height: 12)
      }
    }
  }

  private func color(for index: Int) -> Color {
    switch index {
    case ..<9: .green
    case ..<12: .yellow
    default: .red
    }
  }
}

struct DancingBarsMeter: View {
  @ObservedObject var level: LiveLevel

  var body: some View {
    let value = meterValue(level.rms)
    HStack(spacing: 2.5) {
      ForEach(0 ..< 5, id: \.self) { index in
        // Center-weighted: middle bar tallest, edges shyest.
        let weight = [0.45, 0.8, 1.0, 0.8, 0.45][index]
        let jitter = [0.9, 1.06, 1.0, 0.96, 1.1][index]
        let height = max(3, 16 * value * weight * jitter)
        Capsule()
          .fill(Color.accentColor)
          .frame(width: 3, height: height)
      }
    }
    .frame(height: 16, alignment: .center)
    .animation(.linear(duration: 0.05), value: value)
  }
}

struct MicGlyphMeter: View {
  @ObservedObject var level: LiveLevel

  var body: some View {
    let value = meterValue(level.rms)
    Image(systemName: "microphone", variableValue: value)
      .symbolVariant(.fill)
      .font(.system(size: 15))
      .foregroundStyle(Color.accentColor)
      .background(
        Circle()
          .fill(Color.accentColor.opacity(0.16))
          .frame(width: 26 + 10 * value, height: 26 + 10 * value)
          .animation(.linear(duration: 0.06), value: value)
      )
      .frame(width: 40, height: 24)
  }
}

struct WaveformMeter: View {
  @ObservedObject var level: LiveLevel

  var body: some View {
    HStack(alignment: .center, spacing: 1.5) {
      ForEach(Array(level.history.enumerated()), id: \.offset) { entry in
        let v = meterValue(entry.element)
        Capsule()
          .fill(Color.accentColor.opacity(0.35 + 0.65 * v))
          .frame(width: 1.5, height: max(2, 16 * v))
      }
    }
    .frame(width: 144, height: 16)
  }
}

struct ArcGaugeMeter: View {
  @ObservedObject var level: LiveLevel

  var body: some View {
    let value = meterValue(level.rms)
    ZStack {
      Circle()
        .trim(from: 0, to: 0.75)
        .stroke(.quaternary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        .rotationEffect(.degrees(135))
      Circle()
        .trim(from: 0, to: 0.75 * value)
        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        .rotationEffect(.degrees(135))
        .animation(.linear(duration: 0.05), value: value)
      Image(systemName: "microphone.fill")
        .font(.system(size: 8))
        .foregroundStyle(.secondary)
    }
    .frame(width: 22, height: 22)
  }
}

// MARK: - Harness

struct VariantRow: View {
  let label: String
  let caption: String
  let meter: AnyView

  var body: some View {
    HStack(spacing: 14) {
      Text(label)
        .font(.system(size: 13, weight: .semibold, design: .monospaced))
        .foregroundStyle(.secondary)
        .frame(width: 18)
      // The meter in situ: a faithful settings-row mock around it.
      HStack {
        Text("Input")
        Spacer()
        meter
        Text("System Default (MacBook Pro Microphone)")
          .foregroundStyle(.primary)
          .font(.system(size: 12))
        Image(systemName: "chevron.up.chevron.down")
          .font(.system(size: 9))
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 9)
      .background(RoundedRectangle(cornerRadius: 8).fill(.quinary))
      Text(caption)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .frame(width: 150, alignment: .leading)
    }
  }
}

struct MockupView: View {
  @StateObject var level = LiveLevel()

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Live meter treatments — hum to compare. No smoothing anywhere.")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)
      VariantRow(
        label: "a", caption: "thermometer + decaying peak-hold tick",
        meter: AnyView(ThermometerMeter(level: level)),
      )
      VariantRow(
        label: "b", caption: "segmented LEDs, gear idiom",
        meter: AnyView(SegmentedMeter(level: level)),
      )
      VariantRow(
        label: "c", caption: "dancing bars, voice-glyph idiom",
        meter: AnyView(DancingBarsMeter(level: level)),
      )
      VariantRow(
        label: "d", caption: "mic glyph fills + breathing halo",
        meter: AnyView(MicGlyphMeter(level: level)),
      )
      VariantRow(
        label: "e", caption: "scrolling waveform history (~1s)",
        meter: AnyView(WaveformMeter(level: level)),
      )
      VariantRow(
        label: "f", caption: "arc gauge around mic",
        meter: AnyView(ArcGaugeMeter(level: level)),
      )
    }
    .padding(24)
    .frame(width: 760)
    .onAppear { level.start() }
  }
}

// MARK: - App bootstrap

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let appearanceArg = CommandLine.arguments.dropFirst().first
let window = NSWindow(
  contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
  styleMask: [.titled, .closable], backing: .buffered, defer: false,
)
window.title = "Level Meter Mockup"
if let appearanceArg {
  window.appearance = NSAppearance(named: appearanceArg == "light" ? .aqua : .darkAqua)
}
window.contentView = NSHostingView(rootView: MockupView())
window.center()
window.makeKeyAndOrderFront(nil)
print("window.windowNumber=\(window.windowNumber)")
fflush(stdout)
app.activate(ignoringOtherApps: true)
app.run()
