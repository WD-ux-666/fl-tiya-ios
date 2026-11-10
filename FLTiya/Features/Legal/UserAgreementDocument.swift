import Foundation

struct UserAgreementDocument: Decodable, Sendable {
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
    let notice: String
    let sections: [Section]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case documentVersion = "document_version"
        case effectiveDate = "effective_date"
        case title, status, contact, notice, sections
    }

    var statusText: String {
        status == "draft" ? "Draft · Not yet effective" : "Effective: \(effectiveDate ?? "")"
    }

    static func bundled(in bundle: Bundle = .main) -> Self? {
        guard let url = bundle.url(forResource: "UserAgreement", withExtension: "json"),
              let data = try? Data(contentsOf: url), data.count <= 128 * 1024,
              let document = try? JSONDecoder().decode(Self.self, from: data),
              document.isValid else { return nil }
        return document
    }

    private var isValid: Bool {
        func bounded(_ value: String, maximum: Int) -> Bool {
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= maximum
        }
        func identifier(_ value: String) -> Bool {
            bounded(value, maximum: 80)
                && value.range(of: "[^A-Za-z0-9._-]", options: .regularExpression) == nil
        }
        let validDate = effectiveDate?.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil
        let validStatus = (status == "draft" && effectiveDate == nil)
            || (status == "effective" && effectiveDate?.count == 10 && validDate)
        return schemaVersion == 1 && identifier(documentVersion)
            && bounded(title, maximum: 120) && bounded(notice, maximum: 3_000)
            && bounded(contact, maximum: 254)
            && contact.range(of: "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$", options: .regularExpression) != nil
            && validStatus && !sections.isEmpty && sections.count <= 40
            && Set(sections.map(\.id)).count == sections.count
            && sections.allSatisfy {
                identifier($0.id) && bounded($0.title, maximum: 160) && bounded($0.text, maximum: 12_000)
            }
    }
}
