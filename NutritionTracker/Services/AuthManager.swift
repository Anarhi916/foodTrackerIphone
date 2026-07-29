import Foundation
import AuthenticationServices
import CryptoKit

// Управление пользовательской сессией: вход через Apple (нативно) / Google (web-OAuth),
// хранение access/refresh в Keychain, обновление сессии, выход, удаление аккаунта.
// Данные приложения остаются локальными (SwiftData) — синк отдельная фаза.
@MainActor
final class AuthManager: NSObject, ObservableObject {
    static let shared = AuthManager()

    @Published private(set) var isSignedIn: Bool
    @Published var isBusy = false
    @Published var errorMessage: String?

    // Токены (актор NetworkService читает access через nonisolated-геттер ниже).
    private(set) var accessTokenValue: String?
    private var refreshTokenValue: String?

    private override init() {
        let access = KeychainService.get(KeychainService.accessKey)
        let refresh = KeychainService.get(KeychainService.refreshKey)
        self.accessTokenValue = access
        self.refreshTokenValue = refresh
        self.isSignedIn = (refresh != nil)
        super.init()
    }

    // Текущий nonce для Apple (SHA256 кладётся в запрос, сырой сверяется бэком).
    private var currentAppleRawNonce: String?
    private var appleContinuation: CheckedContinuation<Void, Error>?
    private var webAuthSession: ASWebAuthenticationSession?
    private var pendingGoogleCodeVerifier: String?

    // MARK: - Доступ к токену для NetworkService (actor)

    // NetworkService — actor; читает токен через async-обёртку.
    var accessToken: String? { accessTokenValue }

    // MARK: - Сохранение/сброс сессии

    private func store(_ tokens: TokenResponse) {
        accessTokenValue = tokens.accessToken
        refreshTokenValue = tokens.refreshToken
        KeychainService.set(tokens.accessToken, for: KeychainService.accessKey)
        KeychainService.set(tokens.refreshToken, for: KeychainService.refreshKey)
        isSignedIn = true
    }

    private func clearSession() {
        accessTokenValue = nil
        refreshTokenValue = nil
        KeychainService.clearAll()
        isSignedIn = false
    }

    // MARK: - Refresh (вызывается из NetworkService при 401)

    func tryRefresh() async -> Bool {
        guard let refresh = refreshTokenValue else { return false }
        do {
            let tokens = try await NetworkService.shared.refreshSession(refreshToken: refresh)
            store(tokens)
            return true
        } catch {
            clearSession()
            return false
        }
    }

    // MARK: - Выход / удаление

    func signOut() async {
        if let refresh = refreshTokenValue {
            await NetworkService.shared.logout(refreshToken: refresh)
        }
        clearSession()
    }

    func deleteAccount() async {
        guard let access = accessTokenValue else { clearSession(); return }
        do {
            try await NetworkService.shared.deleteAccount(accessToken: access)
        } catch {
            // даже при ошибке сети — локально разлогиниваем
        }
        clearSession()
    }

    // MARK: - Sign in with Apple (нативно)

    func signInWithApple() {
        let rawNonce = Self.randomNonce()
        currentAppleRawNonce = rawNonce
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(rawNonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        isBusy = true
        errorMessage = nil
        controller.performRequests()
    }

    // MARK: - Sign in with Google (PKCE authorization code flow via ASWebAuthenticationSession)

    func signInWithGoogle() {
        isBusy = true
        errorMessage = nil
        let codeVerifier = Self.randomNonce(length: 43) // PKCE verifier (43-128 chars)
        let codeChallenge = Self.sha256Base64url(codeVerifier)
        pendingGoogleCodeVerifier = codeVerifier
        let scheme = APIConfig.googleRedirectScheme
        let redirectUri = "\(scheme):/oauth2redirect"
        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            .init(name: "client_id",             value: APIConfig.googleClientId),
            .init(name: "redirect_uri",          value: redirectUri),
            .init(name: "response_type",         value: "code"),
            .init(name: "scope",                 value: "openid email"),
            .init(name: "code_challenge",        value: codeChallenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        guard let authURL = comps.url else { isBusy = false; return }

        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: scheme) { [weak self] callback, error in
            guard let self else { return }
            Task { @MainActor in
                self.isBusy = false
                guard let callback,
                      let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                          .queryItems?.first(where: { $0.name == "code" })?.value else {
                    if error != nil { self.errorMessage = "Вход через Google отменён" }
                    return
                }
                await self.exchangeGoogleCode(code: code, codeVerifier: codeVerifier, redirectUri: redirectUri)
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        webAuthSession = session
        session.start()
    }

    private func exchangeGoogleCode(code: String, codeVerifier: String, redirectUri: String) async {
        do {
            let tokens = try await NetworkService.shared.authGoogleCode(
                code: code, codeVerifier: codeVerifier, redirectUri: redirectUri,
                clientId: APIConfig.googleClientId
            )
            store(tokens)
        } catch {
            errorMessage = "Не удалось войти через Google"
        }
    }

    // MARK: - Helpers

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if Int(random) < charset.count {
                result.append(charset[Int(random) % charset.count])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }

    // Base64url (no padding) SHA256 — used as PKCE code_challenge.
    private static func sha256Base64url(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return Data(hashed).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func param(_ name: String, inFragment fragment: String) -> String? {
        for pair in fragment.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2, kv[0] == name {
                return kv[1].removingPercentEncoding
            }
        }
        return nil
    }
}

// MARK: - Apple delegate

extension AuthManager: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = cred.identityToken,
              let identityToken = String(data: tokenData, encoding: .utf8),
              let rawNonce = currentAppleRawNonce else {
            isBusy = false
            errorMessage = "Apple не вернул токен"
            return
        }
        Task { @MainActor in
            defer { isBusy = false }
            do {
                let tokens = try await NetworkService.shared.authApple(identityToken: identityToken, nonce: rawNonce)
                store(tokens)
            } catch {
                errorMessage = "Не удалось войти через Apple"
            }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        isBusy = false
        // Отмена пользователем — не показываем как ошибку.
        if (error as? ASAuthorizationError)?.code != .canceled {
            errorMessage = "Вход через Apple не удался"
        }
    }
}

// MARK: - Presentation anchor (Apple + Google web session)

extension AuthManager: ASAuthorizationControllerPresentationContextProviding, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        anchor()
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor()
    }
    private func anchor() -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        return scene?.keyWindow ?? ASPresentationAnchor()
    }
}
