import Foundation
import Supabase

/// Public project settings. Credentials with server privileges never enter the app client.
struct BackendConfiguration {
    let projectURL: URL
    let publishableKey: String
    let appleSignInEnabled: Bool

    init(projectURL: String, publishableKey: String, appleSignInEnabled: Bool) throws {
        let address = projectURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: address),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              host.hasSuffix(".supabase.co"),
              components.user == nil, components.password == nil,
              components.port == nil, components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/" else {
            throw ConfigurationError.invalidProjectURL
        }
        let reference = String(host.dropLast(".supabase.co".count))
        let allowedHostCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        guard !reference.isEmpty,
              reference.unicodeScalars.allSatisfy({ allowedHostCharacters.contains($0) }),
              let url = URL(string: "https://\(host)") else {
            throw ConfigurationError.invalidProjectURL
        }

        let key = publishableKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isPublicClientKey(key) else { throw ConfigurationError.invalidPublicKey }
        self.projectURL = url
        self.publishableKey = key
        self.appleSignInEnabled = appleSignInEnabled
    }

    static func load(bundle: Bundle = .main) -> BackendConfiguration? {
        guard let file = bundle.url(forResource: "SupabaseConfig", withExtension: "plist"),
              let data = try? Data(contentsOf: file),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let values = object as? [String: Any],
              let projectURL = values["ProjectURL"] as? String,
              let publicKey = values["PublishableKey"] as? String else { return nil }
        return try? BackendConfiguration(
            projectURL: projectURL,
            publishableKey: publicKey,
            appleSignInEnabled: values["AppleSignInEnabled"] as? Bool ?? false
        )
    }

    var authStorageKey: String { "sb-\(projectReference)-auth-token" }

    func keychainService(bundleIdentifier: String) -> String {
        "\(bundleIdentifier).supabase.auth"
    }

    func signedOutPreferenceKey(bundleIdentifier: String) -> String {
        "\(bundleIdentifier).supabase.\(projectReference).signedOut"
    }

    private var projectReference: String {
        String((projectURL.host ?? "").dropLast(".supabase.co".count))
    }

    private static func isPublicClientKey(_ key: String) -> Bool {
        let prefix = "sb_publishable_"
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        if key.hasPrefix(prefix) {
            let value = key.dropFirst(prefix.count)
            return !value.isEmpty && value.unicodeScalars.allSatisfy { allowed.contains($0) }
        }
        // Compatibility with legacy anon keys only. This identifies the key type;
        // Supabase verifies the key itself when handling requests.
        let parts = key.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy { allowed.contains($0) } }) else {
            return false
        }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data),
              let claims = object as? [String: Any] else { return false }
        return claims["role"] as? String == "anon"
    }

    enum ConfigurationError: Error {
        case invalidProjectURL
        case invalidPublicKey
    }
}

@MainActor
enum SupabaseClientFactory {
    static func makeClient() -> SupabaseClient? {
        #if DEVELOPMENT_PREVIEW
        return nil
        #else
        guard let configuration = BackendConfiguration.load(),
              let bundleIdentifier = Bundle.main.bundleIdentifier else { return nil }
        return SupabaseClient(
            supabaseURL: configuration.projectURL,
            supabaseKey: configuration.publishableKey,
            options: .init(auth: .init(
                storage: DeviceAuthStorage(service: configuration.keychainService(bundleIdentifier: bundleIdentifier)),
                storageKey: configuration.authStorageKey,
                autoRefreshToken: true,
                // UI restoration always verifies /user explicitly; the stream
                // is used only for invalidation, never to unlock cached users.
                emitLocalSessionAsInitialSession: true
            ))
        )
        #endif
    }
}
