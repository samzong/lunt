import Foundation
import LocalAuthentication
import Security

public actor AuthStore {
    public static let shared = AuthStore()

    public static let oauthKey = "github_oauth_access_token"
    private static let service = "com.samzong.lunt.auth"

    private init() {}

    public func currentToken() -> String? {
        read(key: Self.oauthKey)
    }

    public func saveToken(_ token: String) {
        write(token, key: Self.oauthKey)
    }

    public func clearToken() {
        delete(key: Self.oauthKey)
    }

    private func write(_ value: String, key: String) {
        guard let data = value.data(using: .utf8) else { return }
        delete(key: key)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func read(key: String) -> String? {
        let context = LAContext()
        context.interactionNotAllowed = true

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseAuthenticationContext: context,
            kSecUseAuthenticationUI: "u_AuthUIF",
        ]
        var ref: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &ref) == errSecSuccess,
              let data = ref as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private func delete(key: String) -> Bool {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: Self.service,
            kSecAttrAccount: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
