import Foundation
import LocalAuthentication
import AppKit

@Observable
final class AuthService {
    var isUnlocked = false
    var isAuthenticating = false
    var authError: String?

    init() {
        startMonitoring()
    }

    // MARK: - Biometric Auth

    func authenticate() {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                Log.app.warning("No authentication available, granting access")
                isUnlocked = true
                return
            }
            evaluatePolicy(context: context, policy: .deviceOwnerAuthentication)
            return
        }

        evaluatePolicy(context: context, policy: .deviceOwnerAuthenticationWithBiometrics)
    }

    private func evaluatePolicy(context: LAContext, policy: LAPolicy) {
        isAuthenticating = true
        authError = nil

        context.evaluatePolicy(
            policy,
            localizedReason: "Unlock Macbot to access your conversations and data"
        ) { success, error in
            DispatchQueue.main.async {
                self.isAuthenticating = false
                if success {
                    self.isUnlocked = true
                    self.authError = nil
                    Log.app.info("Authentication successful")
                } else {
                    self.isUnlocked = false
                    self.authError = error?.localizedDescription ?? "Authentication failed"
                    Log.app.warning("Authentication failed: \(error?.localizedDescription ?? "unknown")")
                }
            }
        }
    }

    // MARK: - Lock (only on screen lock)

    func lock() {
        isUnlocked = false
        Log.app.info("App locked")
    }

    private func startMonitoring() {
        // Only lock when the SCREEN locks — not on idle, not on app switch
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.lock()
        }
    }

    // MARK: - Database Encryption Key

    static func databaseKey() -> String {
        let keychainKey = "com.macbot.db.encryption"
        if let existing = KeychainManager.get(key: keychainKey) {
            return existing
        }
        var keyData = Data(count: 32)
        _ = keyData.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        let key = keyData.base64EncodedString()
        KeychainManager.set(key: keychainKey, value: key)
        Log.app.info("Generated new database encryption key")
        return key
    }
}
