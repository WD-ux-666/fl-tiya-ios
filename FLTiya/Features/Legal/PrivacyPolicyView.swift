import SwiftUI
import WebKit

struct PrivacyPolicyView: View {
    var showsCloseButton = false

    var body: some View {
        LegalPDFView(kind: .privacyPolicy, showsCloseButton: showsCloseButton) {
            BundledPrivacyPolicyView()
        }
    }
}

struct LegalPDFView<AppCopy: View>: View {
    let kind: LegalPDFKind
    let showsCloseButton: Bool
    @ViewBuilder let appCopy: () -> AppCopy
    @Environment(\.dismiss) private var dismiss
    #if DEBUG
    @Environment(\.exitDevelopmentPreview) private var exitDevelopmentPreview
    #endif
    @State private var phase = LoadPhase.loadingLink
    @State private var attempt = UUID()

    private enum LoadPhase {
        case loadingLink
        case document(LegalPDFReference, isLoading: Bool)
        case unavailable
        case appCopy
    }

    private var isOfflinePreview: Bool {
        #if DEBUG
        exitDevelopmentPreview != nil
        #else
        false
        #endif
    }

    var body: some View {
        Group {
            if isOfflinePreview {
                appCopy()
            } else {
                onlineReader
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { AppBackdrop() }
        .navigationTitle(kind == .privacyPolicy ? "Privacy Policy" : "User Agreement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(AppTheme.accent)
                }
            }
        }
        .task(id: attempt) {
            guard !isOfflinePreview, case .loadingLink = phase else { return }
            do {
                let reference = try await PrivacyPolicyService.pdfReference(for: kind)
                try Task.checkCancellation()
                phase = .document(reference, isLoading: true)
            } catch {
                if !Task.isCancelled { phase = .unavailable }
            }
        }
    }

    @ViewBuilder
    private var onlineReader: some View {
        switch phase {
        case .loadingLink:
            loadingIndicator
        case let .document(reference, isLoading):
            PDFWebView(url: reference.url, onLoad: loadHandler(for: attempt))
                .opacity(isLoading ? 0 : 1)
                .accessibilityHidden(isLoading)
                .overlay {
                    if isLoading { loadingIndicator }
                }
        case .unavailable:
            VStack(spacing: 12) {
                Text("The PDF couldn’t be loaded.")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Button("Try again") {
                    phase = .loadingLink
                    attempt = UUID()
                }
                .frame(minHeight: 44)
                Button("Read app copy") { phase = .appCopy }
                    .frame(minHeight: 44)
            }
            .tint(AppTheme.accent)
            .multilineTextAlignment(.center)
            .padding(24)
        case .appCopy:
            appCopy()
        }
    }

    private var loadingIndicator: some View {
        ProgressView("Loading document…")
            .tint(AppTheme.accent)
            .foregroundStyle(AppTheme.secondaryInk)
    }

    private func loadHandler(for expectedAttempt: UUID) -> (Bool) -> Void {
        { succeeded in
            guard attempt == expectedAttempt, case let .document(reference, _) = phase else { return }
            phase = succeeded ? .document(reference, isLoading: false) : .unavailable
        }
    }
}

private struct PDFWebView: UIViewRepresentable {
    let url: URL
    let onLoad: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(url: url, onLoad: onLoad) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpShouldHandleCookies = false
        request.setValue("application/pdf", forHTTPHeaderField: "Accept")
        context.coordinator.documentNavigation = webView.load(request)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
        webView.stopLoading()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let url: URL
        private let onLoad: (Bool) -> Void
        var documentNavigation: WKNavigation?

        init(url: URL, onLoad: @escaping (Bool) -> Void) {
            self.url = url
            self.onLoad = onLoad
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let isDocument = action.targetFrame?.isMainFrame == true && action.request.url == url
            decisionHandler(isDocument ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            let response = navigationResponse.response as? HTTPURLResponse
            let status = response?.statusCode
            let isPDF = navigationResponse.isForMainFrame && navigationResponse.canShowMIMEType && response?.url == url
                && (status == 200 || status == 206) && response?.mimeType?.lowercased() == "application/pdf"
            decisionHandler(isPDF ? .allow : .cancel)
            if navigationResponse.isForMainFrame && !isPDF { onLoad(false) }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if navigation === documentNavigation { onLoad(true) }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if navigation === documentNavigation { onLoad(false) }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if navigation === documentNavigation { onLoad(false) }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            onLoad(false)
        }
    }
}

private struct BundledPrivacyPolicyView: View {
    private let document = PrivacyPolicyDocument.bundled()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let document {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: document.title)
                            .font(.title.weight(.bold))
                            .accessibilityAddTraits(.isHeader)
                        Text(verbatim: document.statusText)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.secondaryInk)
                        Text(verbatim: "Contact: \(document.contact)")
                            .font(.subheadline.weight(.semibold))
                            .textSelection(.enabled)
                        if document.contactIsPlaceholder {
                            Text("This draft contact is a placeholder and cannot receive requests.")
                                .font(.footnote)
                                .foregroundStyle(AppTheme.secondaryInk)
                        }
                    }
                    Text(verbatim: "App copy · Available offline\nVersion: \(document.documentVersion)")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryInk)
                    Text(verbatim: document.notice)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryInk)
                    ForEach(document.sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(verbatim: section.title)
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                            Text(verbatim: section.text)
                                .font(.body)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                } else {
                    Text("The app copy of the privacy policy couldn’t be loaded.")
                        .foregroundStyle(AppTheme.secondaryInk)
                }
            }
            .padding(24)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .foregroundStyle(AppTheme.ink)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        PrivacyPolicyView()
            .environment(\.exitDevelopmentPreview, {})
    }
}
#endif
