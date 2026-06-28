//
//  Passkeys.swift
//  Django Files
//
//  WebAuthn / passkey login support.
//
//  The backend exposes a session-cookie based ceremony at /oauth/passkey/auth/{begin,complete}.
//  This file:
//    1. Drives a platform passkey assertion via ASAuthorizationController.
//    2. Carries the Django session cookie set by /begin through to /complete.
//    3. Exchanges the resulting authenticated session for a Bearer token via
//       POST /api/auth/token/ (which returns a token when the request already
//       has a valid session).
//

import AuthenticationServices
import Foundation
import UIKit

extension Data {
    /// RFC 4648 base64url, no padding. py_webauthn on the server emits and accepts this form.
    func base64URLEncodedString() -> String {
        return base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded input: String) {
        var s = input.replacingOccurrences(of: "-", with: "+")
                     .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - s.count % 4) % 4
        s.append(String(repeating: "=", count: pad))
        self.init(base64Encoded: s)
    }
}

// MARK: - Wire format

/// Subset of PublicKeyCredentialRequestOptions emitted by py_webauthn's options_to_json().
/// All binary fields are base64url-encoded.
struct DFPasskeyAuthOptions: Decodable {
    let challenge: String
    let rpId: String
    let timeout: Int?
    let userVerification: String?
    let allowCredentials: [AllowCredential]?

    struct AllowCredential: Decodable {
        let id: String
        let type: String
    }
}

enum DFPasskeyError: LocalizedError {
    case notEnabled(String)
    case http(Int, String?)
    case canceled
    case ceremonyFailed(String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .notEnabled(let msg): return msg
        case .http(let code, let msg): return msg ?? "Server returned \(code)."
        case .canceled: return "Passkey sign-in canceled."
        case .ceremonyFailed(let msg): return msg
        case .decoding: return "Unexpected response from server."
        }
    }
}

// MARK: - DFAPI extension: passkey HTTP calls

extension DFAPI {
    /// Cookie-persistent session used to carry the Django session cookie across
    /// /begin → /complete → /api/auth/token/. Caller owns it for the ceremony's lifetime.
    static func makePasskeyURLSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        return URLSession(configuration: config)
    }

    private static var passkeyDecoder: JSONDecoder {
        // The default DFAPI decoder converts from snake_case, which would mangle
        // WebAuthn's camelCase fields (rpId, userVerification). Use a vanilla decoder.
        return JSONDecoder()
    }

    /// POST /oauth/passkey/auth/begin — returns assertion options and seeds the session cookie.
    public func getPasskeyAuthOptions(using session: URLSession) async throws -> DFPasskeyAuthOptions {
        let endpoint = self.url.appendingPathComponent("oauth/passkey/auth/begin")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue(DFAPI.customUserAgent, forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw DFPasskeyError.decoding }
        if http.statusCode != 200 {
            throw DFPasskeyError.http(http.statusCode, decodeServerError(data))
        }
        do {
            return try DFAPI.passkeyDecoder.decode(DFPasskeyAuthOptions.self, from: data)
        } catch {
            throw DFPasskeyError.decoding
        }
    }

    /// POST /oauth/passkey/auth/complete — verifies the assertion and authenticates the session.
    public func completePasskeyAuth(body: Data, using session: URLSession) async throws {
        let endpoint = self.url.appendingPathComponent("oauth/passkey/auth/complete")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(DFAPI.customUserAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = body
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw DFPasskeyError.decoding }
        if http.statusCode != 200 {
            throw DFPasskeyError.http(http.statusCode, decodeServerError(data))
        }
    }

    /// POST /api/auth/token/ — when the session is already authenticated (e.g. via passkey),
    /// the backend returns a fresh Bearer token without needing a username/password body.
    public func issueTokenForCurrentSession(using session: URLSession) async throws -> String {
        let endpoint = encodeParametersIntoURL(path: getAPIPath(.login), parameters: [:])
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue(DFAPI.customUserAgent, forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            throw DFPasskeyError.http(code, decodeServerError(data))
        }
        do {
            return try JSONDecoder().decode(UserToken.self, from: data).token
        } catch {
            throw DFPasskeyError.decoding
        }
    }

    private func decodeServerError(_ data: Data) -> String? {
        struct E: Decodable { let error: String? }
        if let e = try? JSONDecoder().decode(E.self, from: data), let msg = e.error, !msg.isEmpty {
            return msg
        }
        return nil
    }
}

// MARK: - Ceremony coordinator

/// Drives a single platform-passkey assertion. Built as an `NSObject` because
/// `ASAuthorizationController` requires Objective-C delegate conformance, but
/// exposes an `async` `signIn(...)` for SwiftUI callers.
///
/// Note: ``ASAuthorizationPlatformPublicKeyCredentialProvider`` requires the
/// relying-party domain to be listed in the app's Associated Domains
/// (``webcredentials:<host>``). For arbitrary self-hosted servers this entitlement
/// will not match, and the OS surfaces a "credential not found" style error.
/// The user must associate their server's domain with this app for passkey
/// login to work end-to-end.
final class PasskeyAuthCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {

    private var continuation: CheckedContinuation<ASAuthorizationPlatformPublicKeyCredentialAssertion, Error>?
    private weak var anchorWindow: UIWindow?

    /// Runs the platform-passkey assertion ceremony. Returns the assertion on success;
    /// throws ``DFPasskeyError`` on cancellation/failure.
    @MainActor
    func requestAssertion(rpId: String, challenge: Data, allowedCredentialIDs: [Data]) async throws -> ASAuthorizationPlatformPublicKeyCredentialAssertion {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rpId)
        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        if !allowedCredentialIDs.isEmpty {
            request.allowedCredentials = allowedCredentialIDs.map {
                ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0)
            }
        }
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        anchorWindow = Self.activeKeyWindow()
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            controller.performRequests()
        }
    }

    // MARK: ASAuthorizationControllerDelegate

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let assertion = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
            continuation?.resume(throwing: DFPasskeyError.ceremonyFailed("Unexpected credential type."))
            continuation = nil
            return
        }
        continuation?.resume(returning: assertion)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let mapped: Error
        if let asError = error as? ASAuthorizationError {
            switch asError.code {
            case .canceled: mapped = DFPasskeyError.canceled
            default: mapped = DFPasskeyError.ceremonyFailed(asError.localizedDescription)
            }
        } else {
            mapped = DFPasskeyError.ceremonyFailed(error.localizedDescription)
        }
        continuation?.resume(throwing: mapped)
        continuation = nil
    }

    // MARK: ASAuthorizationControllerPresentationContextProviding

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return anchorWindow ?? Self.activeKeyWindow() ?? ASPresentationAnchor()
    }

    @MainActor
    private static func activeKeyWindow() -> UIWindow? {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}

// MARK: - High-level entry point

extension DFAPI {

    /// Runs the full passkey sign-in flow against this server and stores the
    /// resulting Bearer token on `selectedServer`. Returns true on success.
    @MainActor
    public func passkeyLogin(selectedServer: DjangoFilesSession) async throws -> Bool {
        let session = DFAPI.makePasskeyURLSession()

        let options = try await getPasskeyAuthOptions(using: session)
        guard let challenge = Data(base64URLEncoded: options.challenge) else {
            throw DFPasskeyError.decoding
        }
        let allowed: [Data] = (options.allowCredentials ?? []).compactMap {
            Data(base64URLEncoded: $0.id)
        }

        let coordinator = PasskeyAuthCoordinator()
        let assertion = try await coordinator.requestAssertion(
            rpId: options.rpId,
            challenge: challenge,
            allowedCredentialIDs: allowed
        )

        let body = try buildAssertionBody(from: assertion)
        try await completePasskeyAuth(body: body, using: session)

        let token = try await issueTokenForCurrentSession(using: session)

        // Persist token + the session cookies (sessionid / csrftoken) on the
        // server model so WebView and subsequent API calls stay authenticated.
        let cookies = session.configuration.httpCookieStorage?.cookies(for: self.url) ?? []
        cookies.forEach { HTTPCookieStorage.shared.setCookie($0) }
        selectedServer.cookies = cookies
        selectedServer.token = token
        selectedServer.auth = true
        return true
    }

    private func buildAssertionBody(from assertion: ASAuthorizationPlatformPublicKeyCredentialAssertion) throws -> Data {
        let credentialIdB64 = assertion.credentialID.base64URLEncodedString()
        let userHandle: Any = assertion.userID.isEmpty ? NSNull() : assertion.userID.base64URLEncodedString()
        let response: [String: Any] = [
            "clientDataJSON": assertion.rawClientDataJSON.base64URLEncodedString(),
            "authenticatorData": assertion.rawAuthenticatorData.base64URLEncodedString(),
            "signature": assertion.signature.base64URLEncodedString(),
            "userHandle": userHandle,
        ]
        let payload: [String: Any] = [
            "id": credentialIdB64,
            "rawId": credentialIdB64,
            "type": "public-key",
            "response": response,
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [])
    }
}
