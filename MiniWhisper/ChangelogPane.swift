import AppSettings
import Foundation
import SwiftUI

// MARK: - ChangelogPane

struct ChangelogPane: View {
  // MARK: Lifecycle

  init(
    changelog: Changelog = Channel.bundledChangelog,
    channelKind: Channel.Kind = Channel.kind,
    installedVersion: String = Channel.shortVersion,
  ) {
    releases = changelog.visibleReleases(includeUnreleased: channelKind.includesUnreleasedChangelog)
    self.channelKind = channelKind
    self.installedVersion = installedVersion
  }

  // MARK: Internal

  var body: some View {
    if releases.isEmpty {
      ContentUnavailableView("No Release Notes", systemImage: "doc.text")
        .accessibilityIdentifier(AccessibilityID.changelogContent)
        .accessibilityLabel("Changelog")
    } else {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          ForEach(Array(releases.enumerated()), id: \.element.id) { index, release in
            if index > 0 {
              Divider()
            }
            ReleaseBlock(
              title: Self.sectionTitle(for: release, channelKind: channelKind),
              release: release,
              badge: Self.badge(
                for: release, channelKind: channelKind, installedVersion: installedVersion,
              ),
            )
          }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier(AccessibilityID.changelogContent)
      .accessibilityLabel("Changelog")
    }
  }

  static func sectionTitle(for release: Changelog.Release, channelKind: Channel.Kind) -> String {
    switch release.kind {
    case .unreleased:
      switch channelKind {
      case .nightly:
        "Nightly"
      case .dev:
        "Dev"
      case .release:
        release.title
      }
    case let .version(version):
      version
    }
  }

  static func badge(
    for release: Changelog.Release, channelKind: Channel.Kind, installedVersion: String,
  ) -> String? {
    switch release.kind {
    case .unreleased:
      channelKind == .release ? nil : "Installed"
    case let .version(version):
      channelKind == .release && version == installedVersion ? "Installed" : nil
    }
  }

  // MARK: Private

  private let releases: [Changelog.Release]
  private let channelKind: Channel.Kind
  private let installedVersion: String
}

// MARK: - ReleaseBlock

private struct ReleaseBlock: View {
  // MARK: Internal

  let title: String
  let release: Changelog.Release
  let badge: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(title)
          .font(.title2.weight(.semibold))
          .monospacedDigit()
        if let badge {
          Text(badge)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
      .accessibilityElement(children: .combine)

      if let summary = release.summary {
        Text(Self.inlineMarkdown(summary))
          .foregroundStyle(.secondary)
          .lineSpacing(2)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(alignment: .leading, spacing: 14) {
        ForEach(release.sections) { section in
          VStack(alignment: .leading, spacing: 6) {
            if !section.title.isEmpty {
              Text(section.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
              ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                  Text("•")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                  Text(Self.inlineMarkdown(item))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                }
              }
            }
          }
        }
      }
    }
    .frame(maxWidth: 580, alignment: .leading)
  }

  // MARK: Private

  private static func inlineMarkdown(_ text: String) -> AttributedString {
    (try? AttributedString(
      markdown: text,
      options: AttributedString.MarkdownParsingOptions(
        interpretedSyntax: .inlineOnlyPreservingWhitespace,
      ),
    )) ?? AttributedString(text)
  }
}
