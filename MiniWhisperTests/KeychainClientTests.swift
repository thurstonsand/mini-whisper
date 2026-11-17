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
    let slot = CredentialSlot(profile: .everyday, provider: .google)
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

  /// Haiku's key outlives its profile under its old account until the user decides where it goes.
  @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
  func `an orphaned key moves into the slot that takes it over`() throws {
    let service = "com.thurstonsand.MiniWhisperTests.\(UUID())"
    let keychain = KeychainStore(service: service)
    let custom = CredentialSlot(profile: .custom, provider: .endpoint)
    defer { try? keychain.delete(custom) }
    let orphan: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecUseDataProtectionKeychain as String: true,
      kSecAttrService as String: service,
      kSecAttrAccount as String: HaikuRetirement.keyAccount,
      kSecValueData as String: Data("sk-ant-orphan".utf8),
    ]
    let lookup = orphan.filter { $0.key != kSecValueData as String } as CFDictionary
    #expect(SecItemAdd(orphan as CFDictionary, nil) == errSecSuccess)
    try keychain.store("sk-custom-old", slot: custom)

    try keychain.adopt(HaikuRetirement.keyAccount, into: custom)

    #expect(try keychain.read(custom) == "sk-ant-orphan")
    #expect(SecItemCopyMatching(lookup, nil) == errSecItemNotFound)
    // An account with nothing in it leaves the slot with nothing either, so no other endpoint's
    // key is sent where Haiku's should have gone.
    try keychain.adopt(HaikuRetirement.keyAccount, into: custom)
    #expect(try keychain.read(custom) == nil)

    // With nowhere to go, the orphan is deleted.
    #expect(SecItemAdd(orphan as CFDictionary, nil) == errSecSuccess)
    try keychain.adopt(HaikuRetirement.keyAccount, into: nil)
    #expect(SecItemCopyMatching(lookup, nil) == errSecItemNotFound)
  }

  @Test func `a keychain failure reports which operation lost`() {
    let error = KeychainError(operation: .store, status: errSecDuplicateItem)

    #expect(error.description.contains("store"))
    #expect(error.description.contains("\(errSecDuplicateItem)"))
  }
}
