import XCTest
@testable import FLTiya

// Regression sources only. Builds and test execution are not authorized.
final class BackendConfigurationTests: XCTestCase {
    func testValidPublicConfigurationKeepsAppleSignInDisabledUntilConfigured() throws {
        let configuration = try BackendConfiguration(
            projectURL: "https://gpstwmffctwqlcakmvgw.supabase.co",
            publishableKey: "sb_publishable_fixture_key",
            appleSignInEnabled: false
        )

        XCTAssertEqual(configuration.projectURL.host, "gpstwmffctwqlcakmvgw.supabase.co")
        XCTAssertFalse(configuration.appleSignInEnabled)
    }

    func testNonProjectURLsCannotCreateBackendConfiguration() {
        let invalidURLs = [
            "http://gpstwmffctwqlcakmvgw.supabase.co",
            "https://supabase.co",
            "https://gpstwmffctwqlcakmvgw.supabase.co.evil.example",
            "https://nested.gpstwmffctwqlcakmvgw.supabase.co",
            "https://user:password@gpstwmffctwqlcakmvgw.supabase.co",
            "https://gpstwmffctwqlcakmvgw.supabase.co/auth/v1",
            "https://gpstwmffctwqlcakmvgw.supabase.co?secret=value",
            "https://gpstwmffctwqlcakmvgw.supabase.co#fragment"
        ]

        for url in invalidURLs {
            XCTAssertThrowsError(try BackendConfiguration(
                projectURL: url,
                publishableKey: "sb_publishable_fixture_key",
                appleSignInEnabled: true
            ), url)
        }
    }

    func testSecretAndServiceRoleKeysCannotEnterAnAppClient() {
        let invalidKeys = [
            "", "sb_secret_fixture_key", "sb_publishable_",
            "e30.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.signature",
            "e30.eyJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.signature",
            "not-a-public-key"
        ]

        for key in invalidKeys {
            XCTAssertThrowsError(try BackendConfiguration(
                projectURL: "https://gpstwmffctwqlcakmvgw.supabase.co",
                publishableKey: key,
                appleSignInEnabled: true
            ))
        }
    }

    func testBundleIdentifiersHaveDifferentSessionNamespaces() throws {
        let configuration = try BackendConfiguration(
            projectURL: "https://gpstwmffctwqlcakmvgw.supabase.co",
            publishableKey: "sb_publishable_fixture_key",
            appleSignInEnabled: true
        )

        XCTAssertNotEqual(
            configuration.keychainService(bundleIdentifier: "com.fltiya.ios.development"),
            configuration.keychainService(bundleIdentifier: "com.fltiya.ios.development.preview")
        )
    }
}
