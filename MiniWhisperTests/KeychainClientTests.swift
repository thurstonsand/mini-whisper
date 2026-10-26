import AppSettings
import Foundation
@testable import MiniWhisper
import Security
import Testing

// MARK: - KeychainClientTests

/// The only test that writes to the real Keychain. A unique service keeps parallel runs isolated
/// from each other and from every MiniWhisper channel; the item is removed again on the way out.
struct KeychainClientTests {
  /// Unsigned CI cannot access the Data Protection Keychain. Release CI verifies the exported
  /// signature, profile, and access group; this signed app-host test exercises Security.framework.
  @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
  func `a secret is stored, read back, replaced, and deleted`() throws {
    let keychain = KeychainStore(service: "com.thurstonsand.MiniWhisperTests.\(UUID())")
    let slot = CredentialSlot(profile: .haiku, provider: .anthropic)
    defer { try? keychain.delete(slot) }

    #expect(try keychain.read(slot) == nil)

    try keychain.store("sk-smoke-first", slot: slot)
    #expect(try keychain.read(slot) == "sk-smoke-first")

    try keychain.store("sk-smoke-second", slot: slot)
    #expect(try keychain.read(slot) == "sk-smoke-second")

    try keychain.delete(slot)
    #expect(try keychain.read(slot) == nil)

    // Deleting what is already gone is the same outcome, so a failed cleanup cannot cascade.
    try keychain.delete(slot)
  }

  @Test func `a keychain failure reports which operation lost`() {
    let error = KeychainError(operation: .store, status: errSecDuplicateItem)

    #expect(error.description.contains("store"))
    #expect(error.description.contains("\(errSecDuplicateItem)"))
  }
}
