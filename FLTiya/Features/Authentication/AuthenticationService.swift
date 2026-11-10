import Foundation

/// Server-owned account classification. Never derive it from user metadata.
enum AccountCohort: String, Decodable {
    case production
    case development
}

/// An app session returned after Auth and the active server account are verified.
struct UserSession {
    let verifiedUserID: String
    let displayName: String?
    let cohort: AccountCohort
    let isExperience: Bool

    init(verifiedUserID: String, displayName: String? = nil, cohort: AccountCohort = .production,
         isExperience: Bool = false) throws {
        let userID = verifiedUserID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userID.isEmpty, !isExperience || cohort == .production else {
            throw AuthenticationFailure.invalidVerifiedUser
        }
        self.verifiedUserID = userID

        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayName = name?.isEmpty == false ? name : nil
        self.cohort = cohort
        self.isExperience = isExperience
    }

    func requireAllowedCohort() throws {
        #if !DEBUG
        guard cohort == .production else { throw AuthenticationFailure.developmentSessionNotAllowed }
        #endif
    }
}

/// Decoded only from session_context(), after a real Auth /user verification.
struct VerifiedSessionContext: Decodable {
    let userID: UUID
    let displayName: String
    let cohort: AccountCohort
    let isExperience: Bool

    enum CodingKeys: String, CodingKey {
        case userID = "user_id", displayName = "display_name", cohort
        case isExperience = "is_experience"
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        userID = try values.decode(UUID.self, forKey: .userID)
        displayName = try values.decode(String.self, forKey: .displayName)
        cohort = try values.decode(AccountCohort.self, forKey: .cohort)
        isExperience = try values.decodeIfPresent(Bool.self, forKey: .isExperience) ?? false
    }

    func verifiedSession(for authUserID: UUID, isAnonymous: Bool = false) throws -> UserSession {
        guard userID == authUserID, isExperience == isAnonymous else {
            throw AuthenticationFailure.invalidVerifiedUser
        }
        let session = try UserSession(verifiedUserID: userID.uuidString, displayName: displayName,
                                      cohort: cohort, isExperience: isExperience)
        try session.requireAllowedCohort()
        return session
    }
}

/// An ephemeral exchange payload. Never persist or log this value or its fields.
struct AppleAuthenticationPayload {
    let userIdentifier: String
    let identityToken: Data
    let authorizationCode: Data
    let rawNonce: String
    let fullName: PersonNameComponents?
}

@MainActor
protocol AuthenticationService {
    var isAvailable: Bool { get }
    var isExperienceSignInAvailable: Bool { get }
    /// Used only to warn before discarding local credentials after a failed
    /// restore. Cached state never grants an authenticated app session.
    var hasPersistedExperienceSession: Bool { get }
    /// Local confirmed intent only; never evidence that server deletion finished.
    var hasPendingAccountDeletion: Bool { get }
    var isDevelopmentSignInAvailable: Bool { get }
    var maintainsPersistentSession: Bool { get }

    /// The service must verify signature, issuer, audience, expiry and nonce and
    /// return its verified app user. Supabase's native ID-token endpoint performs
    /// this verification; exchanging Apple's authorization code is not required.
    /// The token nonce must equal the lowercase SHA-256 hex of payload.rawNonce,
    /// matching the value sent in the native authorization request.
    func verifyAppleSignIn(_ payload: AppleAuthenticationPayload) async throws -> UserSession
    /// Creates an independent anonymous Auth account without collecting an email.
    func signInForExperience() async throws -> UserSession
    func verifyDevelopmentAccessCode(_ accessCode: String) async throws -> UserSession
    /// Deletes the current server-verified account. Provider revocation must be
    /// configured before a linked Apple account can be removed.
    func deleteAccount() async throws
    /// Deletes only the current authenticated anonymous account on the server.
    func deleteExperienceAccount() async throws
    func restoreSession() async throws -> UserSession?
    /// Synchronously records the user's intent before asynchronous cleanup starts.
    func invalidateLocalSession()
    /// Ends the app session. Revoking the Apple authorization grant for account
    /// disconnection/deletion remains a separate trusted-server integration.
    func signOut() async throws
    func observeSignOut(_ onSignOut: @escaping @MainActor () -> Void) async
}

extension AuthenticationService {
    var isExperienceSignInAvailable: Bool { false }
    var hasPersistedExperienceSession: Bool { false }
    var hasPendingAccountDeletion: Bool { false }
    var isDevelopmentSignInAvailable: Bool { false }
    var maintainsPersistentSession: Bool { false }
    func signInForExperience() async throws -> UserSession {
        throw AuthenticationFailure.unavailable
    }
    func deleteExperienceAccount() async throws { throw AuthenticationFailure.unavailable }
    func deleteAccount() async throws { throw AuthenticationFailure.unavailable }
    func verifyDevelopmentAccessCode(_ accessCode: String) async throws -> UserSession {
        throw AuthenticationFailure.unavailable
    }
    func restoreSession() async throws -> UserSession? { nil }
    func invalidateLocalSession() {}
    func signOut() async throws {}
    func observeSignOut(_ onSignOut: @escaping @MainActor () -> Void) async {}
}

/// A format check for the private Community Testing account selector.
enum ExperienceEmailAddress {
    static func normalized(_ input: String) -> String? {
        let address = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.utf8.count <= 254 else { return nil }
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let local = String(parts[0])
        let domain = String(parts[1])
        let localCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.!#$%&'*+-/=?^_`{|}~")
        guard !local.isEmpty, local.utf8.count <= 64,
              !local.hasPrefix("."), !local.hasSuffix("."), !local.contains(".."),
              local.unicodeScalars.allSatisfy({ localCharacters.contains($0) }) else { return nil }
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        let domainCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        guard labels.count >= 2, let last = labels.last, last.count >= 2,
              labels.allSatisfy({ label in
                  !label.isEmpty && label.utf8.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
                      && label.unicodeScalars.allSatisfy { domainCharacters.contains($0) }
              }) else { return nil }
        return address
    }
}

#if DEBUG && COMMUNITY_TESTING
/// Private test configuration only. The server still verifies each code.
struct CommunityTestAccount: Decodable, Identifiable {
    let displayName: String
    let email: String
    let accessCode: String

    var id: String { email.lowercased() }

    private static let maximumJSONBytes = 12_288

    static var configured: [Self] {
        let launchValue = ProcessInfo.processInfo.environment["FLTIYA_COMMUNITY_TEST_ACCOUNTS"]
        #if targetEnvironment(simulator)
        // The host provisions this file in the simulator app's data container.
        // It is never a bundle resource or part of the signed-in session.
        let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CommunityTestAccounts.json", isDirectory: false)
        return load(launchValue: launchValue, localFile: file)
        #else
        return decodeList(launchValue)
        #endif
    }

    static func load(launchValue: String?, localFile: URL?) -> [Self] {
        let launchedAccounts = decodeList(launchValue)
        if !launchedAccounts.isEmpty { return launchedAccounts }
        guard let localFile, let input = try? FileHandle(forReadingFrom: localFile) else { return [] }
        defer { try? input.close() }
        guard let data = try? input.read(upToCount: maximumJSONBytes + 1) else { return [] }
        return decodeAccounts(data)
    }

    static func decodeList(_ value: String?) -> [Self] {
        guard let value, value.utf8.count <= maximumJSONBytes * 4 / 3,
              let data = Data(base64Encoded: value) else { return [] }
        return decodeAccounts(data)
    }

    private static func decodeAccounts(_ data: Data) -> [Self] {
        guard data.count <= maximumJSONBytes,
              let accounts = try? JSONDecoder().decode([Self].self, from: data),
              accounts.allSatisfy({ account in
                  ExperienceEmailAddress.normalized(account.email) == account.email
                      && !account.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && !account.accessCode.isEmpty && account.accessCode.utf8.count <= 256
                      && !account.accessCode.contains(where: { $0.isWhitespace })
              }),
              Set(accounts.map(\.id)).count == accounts.count,
              Set(accounts.map(\.accessCode)).count == accounts.count else { return [] }
        return accounts
    }

    static func matching(_ input: String, in accounts: [Self]) -> Self? {
        guard let email = ExperienceEmailAddress.normalized(input) else { return nil }
        return accounts.first { $0.id == email.lowercased() }
    }
}
#endif

struct UnavailableAuthenticationService: AuthenticationService {
    let isAvailable = false

    func verifyAppleSignIn(_ payload: AppleAuthenticationPayload) async throws -> UserSession {
        throw AuthenticationFailure.unavailable
    }
}

enum AuthenticationFailure: Error {
    case unavailable
    case invalidCredential
    case invalidVerifiedUser
    case secureRandomUnavailable
    case operationInProgress
    case signOutIncomplete
    case developmentSessionNotAllowed
    case appleDeletionUnavailable
}
