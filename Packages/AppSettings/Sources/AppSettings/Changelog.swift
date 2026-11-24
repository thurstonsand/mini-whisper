import Foundation

// MARK: - Changelog

public struct Changelog: Equatable, Sendable {
  // MARK: Lifecycle

  public init(releases: [Release]) {
    self.releases = releases
  }

  // MARK: Public

  public struct Release: Equatable, Sendable, Identifiable {
    // MARK: Lifecycle

    public init(kind: Kind, summary: String? = nil, sections: [Section] = []) {
      self.kind = kind
      self.summary = summary
      self.sections = sections
    }

    // MARK: Public

    public enum Kind: Equatable, Sendable {
      case unreleased
      case version(String)
    }

    public let kind: Kind
    public let summary: String?
    public let sections: [Section]

    public var id: String {
      switch kind {
      case .unreleased:
        "unreleased"
      case let .version(version):
        version
      }
    }

    public var title: String {
      switch kind {
      case .unreleased:
        "Unreleased"
      case let .version(version):
        version
      }
    }

    public var isUnreleased: Bool {
      kind == .unreleased
    }

    public var isEmpty: Bool {
      let hasSummary = summary.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        ?? false
      return !hasSummary && sections.allSatisfy(\.items.isEmpty)
    }
  }

  public struct Section: Equatable, Sendable, Identifiable {
    // MARK: Lifecycle

    public init(title: String, items: [String]) {
      self.title = title
      self.items = items
    }

    // MARK: Public

    public let title: String
    public let items: [String]

    public var id: String {
      title
    }
  }

  public static let empty = Self(releases: [])

  public let releases: [Release]

  /// Parses the repository's `RELEASE.md` format (`## Unreleased`, `## X.Y.Z`, optional intro
  /// paragraphs, `### Added` / `### Changed` / `### Fixed`, and `- ` / `* ` bullets).
  public static func parse(_ markdown: String) -> Self {
    var releases: [Release] = []

    var currentKind: Release.Kind?
    var summaryParagraphs: [String] = []
    var currentParagraphLines: [String] = []
    var sections: [Section] = []
    var currentSectionTitle: String?
    var currentSectionItems: [String] = []
    var inHTMLComment = false

    func flushParagraph() {
      guard !currentParagraphLines.isEmpty else {
        return
      }
      summaryParagraphs.append(currentParagraphLines.joined(separator: " "))
      currentParagraphLines.removeAll()
    }

    func flushSection() {
      guard let title = currentSectionTitle else {
        return
      }
      if !currentSectionItems.isEmpty {
        sections.append(Section(title: title, items: currentSectionItems))
      }
      currentSectionTitle = nil
      currentSectionItems.removeAll()
    }

    func flushRelease() {
      flushParagraph()
      flushSection()
      guard let kind = currentKind else {
        return
      }
      let summary = summaryParagraphs.isEmpty ? nil : summaryParagraphs.joined(separator: "\n\n")
      releases.append(Release(kind: kind, summary: summary, sections: sections))
      currentKind = nil
      summaryParagraphs.removeAll()
      sections.removeAll()
    }

    let lines = markdown.replacing("\r\n", with: "\n").split(
      separator: "\n", omittingEmptySubsequences: false,
    )

    for rawLine in lines {
      let line = String(rawLine)
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      if inHTMLComment {
        if trimmed.contains("-->") {
          inHTMLComment = false
        }
        continue
      }

      if trimmed.hasPrefix("<!--") {
        if !trimmed.contains("-->") {
          inHTMLComment = true
        }
        continue
      }

      if trimmed.hasPrefix("## ") {
        flushRelease()
        let heading = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
        if heading.caseInsensitiveCompare("unreleased") == .orderedSame {
          currentKind = .unreleased
        } else {
          let version = heading.hasPrefix("v") || heading.hasPrefix("V")
            ? String(heading.dropFirst())
            : heading
          currentKind = .version(version)
        }
        continue
      }

      guard currentKind != nil else {
        continue
      }

      if trimmed.hasPrefix("### ") {
        flushParagraph()
        flushSection()
        currentSectionTitle = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces)
        continue
      }

      if trimmed.isEmpty {
        flushParagraph()
        continue
      }

      if let bullet = extractBullet(from: trimmed) {
        flushParagraph()
        if currentSectionTitle == nil {
          currentSectionTitle = ""
        }
        currentSectionItems.append(bullet)
        continue
      }

      // Wrapped continuation of a bullet item.
      if currentSectionTitle != nil, !currentSectionItems.isEmpty,
         line.first?.isWhitespace == true
      {
        currentSectionItems[currentSectionItems.count - 1].append(" \(trimmed)")
        continue
      }

      // Intro paragraph before any subsection.
      if currentSectionTitle == nil {
        currentParagraphLines.append(trimmed)
      }
    }

    flushRelease()
    return Self(releases: releases)
  }

  /// Releases to present for a running channel. Release builds omit `Unreleased`; Nightly and Dev
  /// include it only when it has content.
  public func visibleReleases(includeUnreleased: Bool) -> [Release] {
    releases.filter { release in
      guard !release.isEmpty else {
        return false
      }
      if release.isUnreleased {
        return includeUnreleased
      }
      return true
    }
  }

  // MARK: Private

  private static func extractBullet(from trimmedLine: String) -> String? {
    if trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") {
      let body = trimmedLine.dropFirst(2).trimmingCharacters(in: .whitespaces)
      return body.isEmpty ? nil : body
    }
    return nil
  }
}
