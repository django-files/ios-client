//
//  DFAnalytics.swift
//  Django Files
//
//  Thin wrapper around FirebaseAnalytics. Helpers here MUST stay PII-free:
//  no URLs, hostnames, tokens, usernames, file names, paths, or IDs.
//
//  Events are no-ops on the iOS simulator so dev/QA traffic doesn't
//  pollute production analytics.
//

import Foundation
import FirebaseAnalytics

enum DFAnalytics {
    enum Event {
        // Firebase auto-collects `app_open`; this is a complementary explicit
        // event so foreground transitions are visible in our own dashboards.
        static let appOpen = "df_app_open"
        static let serverAdded = "server_added"
        static let serverAddFailed = "server_add_failed"
        static let loginMethodSelected = "login_method_selected"
        static let deepLinkOpened = "deep_link_opened"
    }

    enum AuthMethod: String {
        case interactive   // Local username/password or OAuth via LoginView
        case application   // Signature-based deep link (djangofiles://)
    }

    enum LoginMethod: String {
        case local
        case oauth
        case application
    }

    enum AddFailReason: String {
        case invalidURL = "invalid_url"
        case serverCheckFailed = "server_check_failed"
        case duplicate = "duplicate"
        case authFailed = "auth_failed"
    }

    enum DeepLinkKind: String {
        case auth
        case serverList = "server_list"
        case fileList = "file_list"
        case preview
        case album
        case stream
        case unknown
    }

    /// Single gate for whether we report at all. Always false on simulator.
    private static var isReportingEnabled: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    /// Honors the user's preference but never enables collection on simulator.
    static func setCollectionEnabled(_ enabled: Bool) {
        Analytics.setAnalyticsCollectionEnabled(enabled && isReportingEnabled)
    }

    static func logAppOpen() {
        guard isReportingEnabled else { return }
        Analytics.logEvent(Event.appOpen, parameters: nil)
    }

    /// Record a successful server addition. Parameters describe the *shape* of
    /// the action, never the server itself.
    static func logServerAdded(
        authMethod: AuthMethod,
        scheme: String?,
        isFirstServer: Bool,
        setAsDefault: Bool
    ) {
        guard isReportingEnabled else { return }
        Analytics.logEvent(Event.serverAdded, parameters: [
            "auth_method": authMethod.rawValue,
            "scheme": normalizedScheme(scheme),
            "is_first_server": isFirstServer,
            "set_as_default": setAsDefault,
        ])
    }

    static func logServerAddFailed(
        reason: AddFailReason,
        scheme: String?
    ) {
        guard isReportingEnabled else { return }
        Analytics.logEvent(Event.serverAddFailed, parameters: [
            "reason": reason.rawValue,
            "scheme": normalizedScheme(scheme),
        ])
    }

    static func logLoginMethodSelected(_ method: LoginMethod) {
        guard isReportingEnabled else { return }
        Analytics.logEvent(Event.loginMethodSelected, parameters: [
            "method": method.rawValue,
        ])
    }

    static func logDeepLinkOpened(kind: DeepLinkKind) {
        guard isReportingEnabled else { return }
        Analytics.logEvent(Event.deepLinkOpened, parameters: [
            "kind": kind.rawValue,
        ])
    }

    private static func normalizedScheme(_ scheme: String?) -> String {
        switch scheme?.lowercased() {
        case "https": return "https"
        case "http": return "http"
        default: return "other"
        }
    }
}
