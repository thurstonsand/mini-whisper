import AppSettings
import Foundation
import SwiftUI

// MARK: - ChangelogPane

struct ChangelogPane: View {
  // MARK: Lifecycle

  init() {
    releases = Self.defaultReleases
  }

  init(
    changelog: Changelog,
    channelKind: Channel.Kind = Channel.kind,
    installedVersion: String = Channel.shortVersion,
  ) {
    releases = Self.renderReleases(
      from: changelog, channelKind: channelKind, installedVersion: installedVersion,
    )
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
            ReleaseBlock(release: release)
              .equatable()
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

  /// Parsed and formatted once per process on first visit to Changelog, so Markdown parsing never
  /// runs inside SwiftUI's view body on resizes or appearance changes.
  private static let defaultReleases = renderReleases(
    from: Channel.bundledChangelog,
    channelKind: Channel.kind,
    installedVersion: Channel.shortVersion,
  )

  private let releases: [RenderedRelease]

  private static func renderReleases(
    from changelog: Changelog, channelKind: Channel.Kind, installedVersion: String,
  ) -> [RenderedRelease] {
    changelog
      .visibleReleases(includeUnreleased: channelKind.includesUnreleasedChangelog)
      .map { release in
        RenderedRelease(
          id: release.id,
          title: sectionTitle(for: release, channelKind: channelKind),
          badge: badge(for: release, channelKind: channelKind, installedVersion: installedVersion),
          summary: release.summary.map(inlineMarkdown),
          sections: release.sections.map { section in
            RenderedSection(
              id: section.id,
              title: section.title,
              items: section.items.map(inlineMarkdown),
            )
          },
        )
      }
  }

  private static func inlineMarkdown(_ text: String) -> AttributedString {
    (try? AttributedString(
      markdown: text,
      options: AttributedString.MarkdownParsingOptions(
        interpretedSyntax: .inlineOnlyPreservingWhitespace,
      ),
    )) ?? AttributedString(text)
  }
}

// MARK: - RenderedRelease

private struct RenderedRelease: Equatable, Identifiable {
  let id: String
  let title: String
  let badge: String?
  let summary: AttributedString?
  let sections: [RenderedSection]
}

// MARK: - RenderedSection

private struct RenderedSection: Equatable, Identifiable {
  let id: String
  let title: String
  let items: [AttributedString]
}

// MARK: - ReleaseBlock

private struct ReleaseBlock: View, Equatable {
  let release: RenderedRelease

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(release.title)
          .font(.title2.weight(.semibold))
          .monospacedDigit()
        if let badge = release.badge {
          Text(badge)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
      .accessibilityElement(children: .combine)

      if let summary = release.summary {
        Text(summary)
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
                  Text(item)
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
}
