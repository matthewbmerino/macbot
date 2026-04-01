import Foundation
import KeychainAccess

enum KeychainManager {
    private static let keychain = Keychain(service: "com.macbot")

    static func set(key: String, value: String) {
        keychain[key] = value
    }

    static func get(key: String) -> String? {
        keychain[key]
    }

    static func delete(key: String) {
        try? keychain.remove(key)
    }
}
