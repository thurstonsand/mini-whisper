import AppKit
import SwiftUI

@MainActor final class AboutWindowController {
  private var window: NSWindow?

  func present() {
    if let window {
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
      return
    }

    let window = NSWindow(
      contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered,
      defer: false)
    window.title = "About MiniWhisper"
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isReleasedWhenClosed = false
    window.collectionBehavior = [.moveToActiveSpace]
    window.setAccessibilityIdentifier(AccessibilityID.aboutWindow)
    window.setAccessibilityLabel("About MiniWhisper")
    window.setAccessibilityTitle("About MiniWhisper")
    window.contentView = NSHostingView(rootView: AboutView { [weak self] in self?.window?.close() })
    window.setContentSize(NSSize(width: 480, height: 440))
    window.center()
    self.window = window

    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }
}

private struct AboutView: View {
  let close: () -> Void

  private var version: String {
    let shortVersion =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
    return "Version \(shortVersion) (\(build))"
  }

  var body: some View {
    VStack(spacing: 0) {
      Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 80, height: 80)
        .accessibilityIdentifier(AccessibilityID.aboutIcon).accessibilityLabel("MiniWhisper icon")
      Text("MiniWhisper").font(.system(size: 26, weight: .semibold)).padding(.top, 12)
        .accessibilityIdentifier(AccessibilityID.aboutAppName).accessibilityLabel("Application")
        .accessibilityValue("MiniWhisper")
      Text(version).font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 4)
        .accessibilityIdentifier(AccessibilityID.aboutVersion).accessibilityLabel("Version")
        .accessibilityValue(version)

      VStack(alignment: .leading, spacing: 8) {
        Text("Speech recognition uses NVIDIA Parakeet TDT 0.6B v2, licensed under CC BY 4.0.")
          .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier(
            AccessibilityID.aboutAttribution
          ).accessibilityLabel("Speech recognition attribution").accessibilityValue(
            "NVIDIA Parakeet TDT 0.6B v2, licensed under CC BY 4.0")
        Link(
          "Parakeet TDT 0.6B v2 on Hugging Face",
          destination: URL(string: "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2")!
        ).accessibilityIdentifier(AccessibilityID.aboutModelLink).accessibilityLabel(
          "Open the Parakeet TDT 0.6B v2 model page")

        Divider().padding(.vertical, 5).accessibilityHidden(true)

        Text("MiniWhisper uses FluidAudio, licensed under the Apache License 2.0.").fixedSize(
          horizontal: false, vertical: true
        ).accessibilityIdentifier(AccessibilityID.aboutFluidAudioAttribution).accessibilityLabel(
          "FluidAudio attribution"
        ).accessibilityValue("FluidAudio, licensed under the Apache License 2.0")
        Link(
          "FluidAudio on GitHub",
          destination: URL(string: "https://github.com/FluidInference/FluidAudio")!
        ).accessibilityIdentifier(AccessibilityID.aboutFluidAudioLink).accessibilityLabel(
          "Open the FluidAudio project page")
      }.font(.system(size: 12)).padding(.top, 28).frame(maxWidth: 390, alignment: .leading)

      Spacer()
      Button("Close", action: close).keyboardShortcut(.cancelAction).accessibilityIdentifier(
        AccessibilityID.aboutClose
      ).accessibilityLabel("Close About MiniWhisper")
    }.accessibilityElement(children: .contain).accessibilityIdentifier(AccessibilityID.aboutContent)
      .accessibilityLabel("About MiniWhisper").padding(.horizontal, 42).padding(.vertical, 32)
      .frame(width: 480, height: 440).background(.background)
  }
}
