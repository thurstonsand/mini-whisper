import ComposableArchitecture
import Foundation
import Security

// MARK: - KeychainAccount

/// Every secret MiniWhisper keeps, named once. The service is the running channel, so the three
/// channels can never read each other's credentials any more than they can share a TCC grant.
enum KeychainAccount: String {
  case cleanupAPIKey = "cleanup-api-key"
}

// MARK: - KeychainClient

/// The app's only non-JSON persistence: generic-password items in the Data Protection Keychain.
/// Existence is answered by reading rather than by a marker in settings, so the file and the
/// keychain cannot disagree about whether a key is there.
@DependencyClient struct KeychainClient {
  var store: @Sendable (String, KeychainAccount) throws -> Void
  var read: @Sendable (KeychainAccount) throws -> String?
  var delete: @Sendable (KeychainAccount) throws -> Void
}

// MARK: DependencyKey

extension KeychainClient: DependencyKey {
  static let liveValue: Self = {
    let keychain = KeychainStore(service: Channel.bundleIdentifier)
    return Self(
      store: { secret, account in try keychain.store(secret, account: account) },
      read: { account in try keychain.read(account) },
      delete: { account in try keychain.delete(account) },
    )
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
  func store(_ secret: String, account: KeychainAccount) throws {
    let secretData = Data(secret.utf8)
    let updates = [kSecValueData as String: secretData] as CFDictionary
    let updated = SecItemUpdate(query(for: account) as CFDictionary, updates)
    switch updated {
    case errSecSuccess:
      return
    case errSecItemNotFound:
      var item = query(for: account)
      item[kSecValueData as String] = secretData
      item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
      let added = SecItemAdd(item as CFDictionary, nil)
      if added == errSecDuplicateItem {
        let retried = SecItemUpdate(query(for: account) as CFDictionary, updates)
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

  func read(_ account: KeychainAccount) throws -> String? {
    var item = query(for: account)
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

  func delete(_ account: KeychainAccount) throws {
    let status = SecItemDelete(query(for: account) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError(operation: .delete, status: status)
    }
  }

  // MARK: Private

  private let service: String

  private func query(for account: KeychainAccount) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecUseDataProtectionKeychain as String: true,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account.rawValue,
    ]
  }
}
