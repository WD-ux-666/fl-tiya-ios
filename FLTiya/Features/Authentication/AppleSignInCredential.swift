import AuthenticationServices
import CryptoKit
import Foundation
import Security

/// The native Apple result, held only long enough to validate and exchange it.
struct AppleSignInCredential {
    let userIdentifier: String
    let identityToken: Data?
    let authorizationCode: Data?
    let state: String?
    let fullName: PersonNameComponents?

    init(
        userIdentifier: String,
        identityToken: Data?,
        authorizationCode: Data?,
        state: String?,
        fullName: PersonNameComponents? = nil
    ) {
        self.userIdentifier = userIdentifier
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
        self.state = state
        self.fullName = fullName
    }

    init(_ credential: ASAuthorizationAppleIDCredential) {
        self.init(
            userIdentifier: credential.user,
            identityToken: credential.identityToken,
            authorizationCode: credential.authorizationCode,
            state: credential.state,
            fullName: credential.fullName
        )
    }

    func validatedPayload(for attempt: AppleSignInAttempt) throws -> AppleAuthenticationPayload {
        guard state == attempt.request.state,
              !userIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let identityToken,
              let token = String(data: identityToken, encoding: .utf8),
              Self.hasCompactTokenFormat(token),
              let authorizationCode,
              let code = String(data: authorizationCode, encoding: .utf8),
              !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AuthenticationFailure.invalidCredential
        }

        return AppleAuthenticationPayload(
            userIdentifier: userIdentifier,
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            rawNonce: attempt.rawNonce,
            fullName: fullName
        )
    }

    /// This checks only transport shape; it does not verify token authenticity.
    private static func hasCompactTokenFormat(_ token: String) -> Bool {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        return segments.count == 3 && segments.allSatisfy { segment in
            !segment.isEmpty && segment.unicodeScalars.allSatisfy { allowed.contains($0) }
        }
    }
}

struct AppleSignInRequest {
    let state: String
    let hashedNonce: String
}

struct AppleSignInAttempt {
    let id = UUID()
    let rawNonce: String
    let request: AppleSignInRequest

    init() throws {
        rawNonce = try Self.secureRandomString()
        request = AppleSignInRequest(
            state: try Self.secureRandomString(),
            hashedNonce: SHA256.hash(data: Data(rawNonce.utf8))
                .map { String(format: "%02x", $0) }.joined()
        )
    }

    private static func secureRandomString() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, buffer.count, baseAddress)
        }
        guard status == errSecSuccess else { throw AuthenticationFailure.secureRandomUnavailable }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
