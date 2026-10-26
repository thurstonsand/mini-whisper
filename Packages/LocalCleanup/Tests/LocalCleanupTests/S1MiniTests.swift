import Foundation
@testable import LocalCleanup
import ModelLibrary
import Testing

// MARK: - S1MiniPromptTests

struct S1MiniPromptTests {
  /// The card's format is load-bearing: the verbatim system prompt, the control line first in
  /// the user turn, and an empty think block so Qwen3 answers rather than reasons.
  @Test func `the prompt is the card's format exactly`() {
    let prompt = S1Mini.prompt("um so hello there", styling: .semiFormal)

    #expect(prompt == """
    <|im_start|>system
    You are a text normalizer for speech-to-text transcripts. The input begins with a control \
    line specifying the styling, structure, and context settings; clean the transcript to match \
    those settings and output only the cleaned text.<|im_end|>
    <|im_start|>user
    [Styling: semi-formal] [Structure: prose] [Context: general]
    um so hello there<|im_end|>
    <|im_start|>assistant
    <think>

    </think>


    """)
  }
}

// MARK: - S1MiniRealAssetTests

/// Opt-in by an installed library root, the same way the engine's real-asset test is.
struct S1MiniRealAssetTests {
  static var root: URL? {
    ProcessInfo.processInfo
      .environment["MINIWHISPER_REAL_ASSET_ROOT"]
      .map(URL.init(fileURLWithPath:))
  }

  @Test(.enabled(if: root != nil))
  func `a disfluent transcript comes back clean, the same way twice`() async throws {
    let library = try ModelLibrary(root: #require(Self.root))
    _ = try library.validate(.s1Mini)
    let model = S1Mini(library: library)
    let loadStarted = ContinuousClock.now
    try await model.prepare()
    let loaded = ContinuousClock.now - loadStarted

    let transcript = "um so i need to uh send the the report by thursday you know"
    let started = ContinuousClock.now
    let first = try await model.clean(transcript)
    let elapsed = ContinuousClock.now - started
    let second = try await model.clean(transcript)
    print("S1MINI load=\(loaded) clean=\(elapsed): \(first)")

    #expect(first == second)
    #expect(!first.localizedCaseInsensitiveContains("um "))
    #expect(first.localizedCaseInsensitiveContains("report"))
    #expect(first.localizedCaseInsensitiveContains("thursday"))
  }
}
