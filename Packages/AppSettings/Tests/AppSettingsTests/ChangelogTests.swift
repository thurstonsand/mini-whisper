import AppSettings
import Testing

struct ChangelogTests {
  @Test func `parses unreleased and versioned releases from RELEASE markdown`() {
    let markdown = """
    <!-- markdownlint-disable MD024 -->

    # Release notes

    ## Unreleased

    ### Added

    - A Changelog pane in Settings.
    - Wrapped bullet line
      that continues cleanly.

    ### Fixed

    - Fixed a subtle hotkey issue.

    ## v0.4.0

    MiniWhisper now reads the window you dictate into.

    ### Added

    - Expanded context.

    ### Changed

    - Everyday cleans up with Gemini 4 Hydrogen.

    ## 0.3.0

    ### Fixed

    - Stopped playing the activate cue twice.
    """

    let changelog = Changelog.parse(markdown)

    #expect(changelog.releases == [
      Changelog.Release(
        kind: .unreleased,
        summary: nil,
        sections: [
          Changelog.Section(
            title: "Added",
            items: [
              "A Changelog pane in Settings.",
              "Wrapped bullet line that continues cleanly.",
            ],
          ),
          Changelog.Section(
            title: "Fixed",
            items: ["Fixed a subtle hotkey issue."],
          ),
        ],
      ),
      Changelog.Release(
        kind: .version("0.4.0"),
        summary: "MiniWhisper now reads the window you dictate into.",
        sections: [
          Changelog.Section(title: "Added", items: ["Expanded context."]),
          Changelog.Section(
            title: "Changed",
            items: ["Everyday cleans up with Gemini 4 Hydrogen."],
          ),
        ],
      ),
      Changelog.Release(
        kind: .version("0.3.0"),
        summary: nil,
        sections: [
          Changelog.Section(title: "Fixed", items: ["Stopped playing the activate cue twice."]),
        ],
      ),
    ])
  }

  @Test func `visibleReleases hides unreleased on stable and omits empty unreleased on nightly`() {
    let populated = Changelog.parse("""
    ## Unreleased

    ### Added

    - New nightly feature.

    ## 0.4.0

    ### Added

    - Stable feature.
    """)

    #expect(populated.visibleReleases(includeUnreleased: false).map(\.id) == ["0.4.0"])
    #expect(populated.visibleReleases(includeUnreleased: true).map(\.id) == ["unreleased", "0.4.0"])

    let emptyUnreleased = Changelog.parse("""
    ## Unreleased

    ### Added

    ## 0.4.0

    ### Added

    - Stable feature.
    """)

    #expect(emptyUnreleased.visibleReleases(includeUnreleased: true).map(\.id) == ["0.4.0"])
    #expect(emptyUnreleased.visibleReleases(includeUnreleased: false).map(\.id) == ["0.4.0"])
  }

  @Test func `parses bullets without a subsection heading and ignores multiline comments`() {
    let markdown = """
    <!--
    multiline comment
    ## 9.9.9
    -->

    ## 0.1.0

    - Initial release.
    """

    let changelog = Changelog.parse(markdown)

    #expect(changelog.releases == [
      Changelog.Release(
        kind: .version("0.1.0"),
        summary: nil,
        sections: [Changelog.Section(title: "", items: ["Initial release."])],
      ),
    ])
  }
}
