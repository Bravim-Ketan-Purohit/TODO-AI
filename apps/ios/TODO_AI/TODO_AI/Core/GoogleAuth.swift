import AuthenticationServices
import UIKit

/// Opens the backend's /auth/google/start in a system auth sheet and captures
/// the todoai://auth?token=… callback.
final class GoogleAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleAuth()
    private var session: ASWebAuthenticationSession?

    /// ephemeral=true forces a fresh browser session — "Use a different account" (4b).
    func signIn(ephemeral: Bool = false) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let s = ASWebAuthenticationSession(url: API.authStartURL,
                                               callbackURLScheme: "todoai") { url, err in
                let token = url.flatMap {
                    URLComponents(url: $0, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "token" })?.value
                }
                if let token {
                    cont.resume(returning: token)
                } else {
                    cont.resume(throwing: err ?? APIError.noSession)
                }
            }
            s.presentationContextProvider = self
            s.prefersEphemeralWebBrowserSession = ephemeral
            self.session = s
            s.start()
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first ?? ASPresentationAnchor()
    }
}
