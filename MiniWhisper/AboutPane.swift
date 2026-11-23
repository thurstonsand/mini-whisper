import AppKit
import SwiftUI

// MARK: - AboutPane

struct AboutPane: View {
  var body: some View {
    Form {
      Section {
        VStack(spacing: 4) {
          Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: 64, height: 64)
            .accessibilityIdentifier(AccessibilityID.aboutIcon)
            .accessibilityLabel("\(Channel.name) icon")
          Text(Channel.name)
            .font(.title2.weight(.semibold))
            .accessibilityIdentifier(AccessibilityID.aboutAppName)
            .accessibilityLabel("Application")
            .accessibilityValue(Channel.name)
          Text("Version \(Channel.version)")
            .foregroundStyle(.secondary)
            .accessibilityIdentifier(AccessibilityID.aboutVersion)
            .accessibilityLabel("Version")
            .accessibilityValue("Version \(Channel.version)")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
      }

      Section("Acknowledgements") {
        Acknowledgement(
          name: "Parakeet TDT 0.6B v2", detail: "Speech recognition · NVIDIA · CC BY 4.0",
          link: "Hugging Face",
          url: URL(string: "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2")!,
          identifier: AccessibilityID.aboutAttribution,
          linkIdentifier: AccessibilityID.aboutModelLink,
          linkLabel: "Open the Parakeet TDT 0.6B v2 model page",
        )
        Acknowledgement(
          name: "FluidAudio", detail: "On-device inference · Apache License 2.0", link: "GitHub",
          url: URL(string: "https://github.com/FluidInference/FluidAudio")!,
          identifier: AccessibilityID.aboutFluidAudioAttribution,
          linkIdentifier: AccessibilityID.aboutFluidAudioLink,
          linkLabel: "Open the FluidAudio project page",
        )
        // The S1-mini license requires this exact name and capitalization wherever it ships.
        Acknowledgement(
          name: "S1-mini by Superwhisper", detail: "Offline cleanup · Apache License 2.0",
          link: "Hugging Face",
          url: URL(string: "https://huggingface.co/superwhisper/s1-mini-GGUF")!,
          identifier: AccessibilityID.aboutS1MiniAttribution,
          linkIdentifier: AccessibilityID.aboutS1MiniLink, linkLabel: "Open the S1-mini model page",
        )
        Acknowledgement(
          name: "llama.cpp", detail: "Runs S1-mini · MIT License", link: "GitHub",
          url: URL(string: "https://github.com/ggml-org/llama.cpp")!,
          identifier: AccessibilityID.aboutLlamaAttribution,
          linkIdentifier: AccessibilityID.aboutLlamaLink,
          linkLabel: "Open the llama.cpp project page",
        )
      }
    }
    .formStyle(.grouped)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(AccessibilityID.aboutContent)
    .accessibilityLabel("About \(Channel.name)")
  }
}

// MARK: - Acknowledgement

private struct Acknowledgement: View {
  let name: String
  let detail: String
  let link: String
  let url: URL
  let identifier: String
  let linkIdentifier: String
  let linkLabel: String

  var body: some View {
    LabeledContent {
      Link(link, destination: url)
        .accessibilityIdentifier(linkIdentifier)
        .accessibilityLabel(linkLabel)
    } label: {
      Text(name)
      Text(detail)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(identifier)
    .accessibilityLabel(name)
  }
}
