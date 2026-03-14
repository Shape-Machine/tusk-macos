import Foundation
import Security

/// Stores connection passwords in the macOS Keychain.
final class KeychainManager: Sendable {
    static let shared = KeychainManager()
    private let service = "com.tusk.app"

    private init() {}

    // MARK: - DB password

    func setPassword(_ password: String, for connectionID: UUID) {
        setItem(password, account: connectionID.uuidString)
    }

    func password(for connectionID: UUID) -> String? {
        item(for: connectionID.uuidString)
    }

    func deletePassword(for connectionID: UUID) {
        deleteItem(account: connectionID.uuidString)
    }

    // MARK: - SSH key passphrase

    func setSshPassphrase(_ passphrase: String, for connectionID: UUID) {
        setItem(passphrase, account: "\(connectionID.uuidString).ssh")
    }

    func sshPassphrase(for connectionID: UUID) -> String? {
        item(for: "\(connectionID.uuidString).ssh")
    }

    func deleteSshPassphrase(for connectionID: UUID) {
        deleteItem(account: "\(connectionID.uuidString).ssh")
    }

    // MARK: - Private helpers

    private func setItem(_ value: String, account: String) {
        let deleteQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        guard !value.isEmpty else { return }

        let addQuery: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrService as String:    service,
            kSecAttrAccount as String:    account,
            kSecValueData as String:      Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private func item(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteItem(account: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
