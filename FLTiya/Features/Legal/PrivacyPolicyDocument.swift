import Foundation

struct PrivacyPolicyDocument: Decodable, Sendable {
    struct Section: Decodable, Identifiable, Sendable {
        let id: String
        let title: String
        let text: String
    }

    let schemaVersion: Int
    let documentVersion: String
    let title: String
    let status: String
    let effectiveDate: String?
    let contact: String
    let contactIsPlaceholder: Bool
    let notice: String
    let sections: [Section]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case documentVersion = "document_version"
        case title, status
        case effectiveDate = "effective_date"
        case contact
        case contactIsPlaceholder = "contact_is_placeholder"
        case notice, sections
    }

    static let maximumBytes = 128 * 1024

    var statusText: String {
        status == "draft" ? "Draft · Not yet effective" : "Effective: \(effectiveDate ?? "")"
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw PrivacyPolicyError.invalidDocument }
        let document = try JSONDecoder().decode(Self.self, from: data)
        try document.validate()
        return document
    }

    static func bundled(in bundle: Bundle = .main) -> Self? {
        guard let url = bundle.url(forResource: "PrivacyPolicy", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let document = try? decode(data) else { return nil }
        return document
    }

    private func validate() throws {
        func bounded(_ value: String, _ maximum: Int) -> Bool {
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= maximum
        }
        func identifier(_ value: String) -> Bool {
            bounded(value, 80) && value.range(of: "[^A-Za-z0-9._-]", options: .regularExpression) == nil
        }
        let validSections = !sections.isEmpty && sections.count <= 40
            && Set(sections.map(\.id)).count == sections.count
            && sections.allSatisfy { identifier($0.id) && bounded($0.title, 160) && bounded($0.text, 12_000) }
        let validContact = bounded(contact, 254)
            && contact.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) != nil
        let validStatus: Bool
        switch status {
        case "draft": validStatus = effectiveDate == nil
        case "effective":
            validStatus = !contactIsPlaceholder
                && effectiveDate?.count == 10
                && effectiveDate?.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil
        default: validStatus = false
        }
        guard schemaVersion == 1, identifier(documentVersion), bounded(title, 120),
              validContact, bounded(notice, 3_000), validSections, validStatus else {
            throw PrivacyPolicyError.invalidDocument
        }
    }
}

private enum PrivacyPolicyError: Error {
    case invalidDocument
    case invalidResponse
}

enum LegalPDFKind: String {
    case privacyPolicy = "privacy_policy"
    case userAgreement = "user_agreement"

    var filename: String {
        switch self {
        case .privacyPolicy: "privacy-policy.pdf"
        case .userAgreement: "user-agreement.pdf"
        }
    }
}

struct LegalPDFReference: Decodable, Sendable {
    let url: URL
    let version: String
}

enum PrivacyPolicyService {
    static let publicURL = URL(string: "https://gpstwmffctwqlcakmvgw.supabase.co/functions/v1/privacy-policy")!
    private static let pdfIndexURL = publicURL.appendingPathComponent("documents")
    private static let documentURL = URL(string: "https://gpstwmffctwqlcakmvgw.supabase.co/functions/v1/privacy-policy?format=json")!

    // Legal content is public before sign-in. Keep account credentials, cookies,
    // identifiers and the authenticated Supabase client out of this request.
    static func fetch() async throws -> PrivacyPolicyDocument {
        let (data, response) = try await publicJSON(at: documentURL, maximumBytes: PrivacyPolicyDocument.maximumBytes)
        let document = try PrivacyPolicyDocument.decode(data)
        if let version = response.value(forHTTPHeaderField: "X-Policy-Version"), version != document.documentVersion {
            throw PrivacyPolicyError.invalidResponse
        }
        return document
    }

    static func pdfReference(for kind: LegalPDFKind) async throws -> LegalPDFReference {
        let (data, _) = try await publicJSON(at: pdfIndexURL, maximumBytes: 8 * 1024)
        let links = try JSONDecoder().decode([String: LegalPDFReference].self, from: data)
        guard let reference = links[kind.rawValue],
              reference.url == publicURL.appendingPathComponent(kind.filename),
              !reference.version.isEmpty, reference.version.count <= 80,
              reference.version.range(of: "[^A-Za-z0-9._-]", options: .regularExpression) == nil else {
            throw PrivacyPolicyError.invalidDocument
        }
        return reference
    }

    private static func publicJSON(at url: URL, maximumBytes: Int) async throws -> (Data, HTTPURLResponse) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        let session = URLSession(configuration: configuration, delegate: PrivacyPolicyRedirectBlocker(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url == url, response.mimeType?.lowercased() == "application/json",
              response.expectedContentLength <= Int64(maximumBytes) else {
            throw PrivacyPolicyError.invalidResponse
        }

        var data = Data()
        for try await byte in bytes {
            guard data.count < maximumBytes else { throw PrivacyPolicyError.invalidDocument }
            data.append(byte)
            if data.count % 4096 == 0 { try Task.checkCancellation() }
        }
        try Task.checkCancellation()
        return (data, response)
    }
}

private final class PrivacyPolicyRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
