import Foundation
import Security
import Supabase

/// SDK session persistence that cannot migrate to another device through a
/// backup. The service/key names stay compatible with existing local sessions.
struct DeviceAuthStorage: AuthLocalStorage {
    let service: String

    func store(key: String, value: Data) throws {
        var attributes = query(key: key)
        attributes[kSecValueData as String] = value
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update: [String: Any] = [
                kSecValueData as String: value,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            try requireSuccess(SecItemUpdate(query(key: key) as CFDictionary, update as CFDictionary))
        } else {
            try requireSuccess(status)
        }
    }

    func retrieve(key: String) throws -> Data? {
        var attributes = query(key: key)
        attributes[kSecReturnData as String] = true
        attributes[kSecReturnAttributes as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try requireSuccess(status)
        guard let item = result as? [String: Any],
              let data = item[kSecValueData as String] as? Data else { throw StorageFailure.invalidData }
        // Upgrade a session originally written by the SDK's default storage.
        if item[kSecAttrAccessible as String] as? String != kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String {
            try requireSuccess(SecItemUpdate(query(key: key) as CFDictionary, [
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ] as CFDictionary))
        }
        return data
    }

    func remove(key: String) throws {
        let status = SecItemDelete(query(key: key) as CFDictionary)
        if status != errSecItemNotFound { try requireSuccess(status) }
    }

    private func query(key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: false
        ]
    }

    private func requireSuccess(_ status: OSStatus) throws {
        #if DEBUG
        if status != errSecSuccess, ProcessInfo.processInfo.environment["FLTIYA_UI_REVIEW_ACCESS_CODE"] != nil {
            NSLog("UIReview keychain status=%d", status)
        }
        #endif
        guard status == errSecSuccess else { throw StorageFailure.keychain(status) }
    }

    private enum StorageFailure: Error {
        case keychain(OSStatus)
        case invalidData
    }
}
