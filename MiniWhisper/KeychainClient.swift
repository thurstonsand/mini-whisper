import AppSettings
import ComposableArchitecture
import Foundation
import Security

// MARK: - KeychainClient

/// The app's only non-JSON persistence: generic-password items in the Data Protection Keychain,
/// one per credential slot. The service is the running channel, so the three channels can never
/// read each other's credentials any more than they can share a TCC grant. Existence is answered
/// by reading rather than by a marker in settings, so the file and the keychain cannot disagree
/// about whether a key is there.
@DependencyClient struct KeychainClient {
  var store: @Sendable (String, CredentialSlot) throws -> Void
  var read: @Sendable (CredentialSlot) throws -> String?
  var delete: @Sendable (CredentialSlot) throws -> Void
  /// Moves the item under an account no slot names any more into a slot, or deletes it when
  /// nothing takes it over. The slot keeps nothing of its own: an empty account empties it.
  var adopt: @Sendable (_ account: String, _ into: CredentialSlot?) throws -> Void
}

// MARK: DependencyKey

extension KeychainClient: DependencyKey {
  static let liveValue: Self = {
    let keychain = KeychainStore(service: Channel.bundleIdentifier)
    return Self(
      store: { secret, slot in try keychain.store(secret, slot: slot) },
      read: { slot in try keychain.read(slot) },
      delete: { slot in try keychain.delete(slot) },
      adopt: { account, slot in try keychain.adopt(account, into: slot) },
    )
  }()

  /// An empty Keychain, as a fresh one is. Writes stay unimplemented: a test that stores a key
  /// has to say so.
  static let testValue: Self = {
    var keychain = Self()
    keychain.read = { _ in nil }
    return keychain
  }()
}

extension DependencyValues {
  var keychain: KeychainClient {
    get { self[KeychainClient.self] }
    set { self[KeychainClient.self] = newValue }
  }
}

// MARK: - KeychainError

struct KeychainError: Error, Equatable {
  enum Operation: String {
    case store
    case read
    case delete
  }

  let operation: Operation
  let status: OSStatus
}

// MARK: CustomStringConvertible

extension KeychainError: CustomStringConvertible {
  var description: String {
    let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
    return "Keychain \(operation.rawValue) failed: \(message) (\(status))"
  }
}

// MARK: - KeychainStore

struct KeychainStore {
  // MARK: Lifecycle

  init(service: String) {
    self.service = service
  }

  // MARK: Internal

  /// An update-then-add rather than delete-then-add, so a failed write leaves the previous key
  /// intact instead of leaving the user with no key at all.
  func store(_ secret: String, slot: CredentialSlot) throws {
    let secretData = Data(secret.utf8)
    let updates = [kSecValueData as String: secretData] as CFDictionary
    let updated = SecItemUpdate(query(for: slot) as CFDictionary, updates)
    switch updated {
    case errSecSuccess:
      return
    case errSecItemNotFound:
      var item = query(for: slot)
      item[kSecValueData as String] = secretData
      item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
      let added = SecItemAdd(item as CFDictionary, nil)
      if added == errSecDuplicateItem {
        let retried = SecItemUpdate(query(for: slot) as CFDictionary, updates)
        guard retried == errSecSuccess else {
          throw KeychainError(operation: .store, status: retried)
        }
        return
      }
      guard added == errSecSuccess else {
        throw KeychainError(operation: .store, status: added)
      }
    default:
      throw KeychainError(operation: .store, status: updated)
    }
  }

  func read(_ slot: CredentialSlot) throws -> String? {
    try read(account: slot.account)
  }

  func delete(_ slot: CredentialSlot) throws {
    try delete(account: slot.account)
  }

  func adopt(_ account: String, into slot: CredentialSlot?) throws {
    if let slot {
      if let secret = try read(account: account) {
        try store(secret, slot: slot)
      } else {
        try delete(slot)
      }
    }
    try delete(account: account)
  }

  // MARK: Private

  private let service: String

  private func read(account: String) throws -> String? {
    var item = query(account: account)
    item[kSecReturnData as String] = true
    item[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(item as CFDictionary, &result)
    switch status {
    case errSecSuccess:
      guard let data = result as? Data, let secret = String(data: data, encoding: .utf8) else {
        throw KeychainError(operation: .read, status: errSecDecode)
      }
      return secret
    case errSecItemNotFound:
      return nil
    default:
      throw KeychainError(operation: .read, status: status)
    }
  }

  private func delete(account: String) throws {
    let status = SecItemDelete(query(account: account) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError(operation: .delete, status: status)
    }
  }

  private func query(for slot: CredentialSlot) -> [String: Any] {
    query(account: slot.account)
  }

  private func query(account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecUseDataProtectionKeychain as String: true,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}
