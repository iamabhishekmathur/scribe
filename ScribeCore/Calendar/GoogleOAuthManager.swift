import Foundation
import AppKit
import os

private let logger = Logger(subsystem: "com.scribe.app", category: "GoogleOAuth")

/// Google OAuth 2.0 PKCE flow for calendar access
public actor GoogleOAuthManager {
    public static let shared = GoogleOAuthManager()

    private let clientId: String
    private let clientSecret: String
    private let redirectURI = "http://127.0.0.1:8089/callback"
    private let authURL = "https://accounts.google.com/o/oauth2/v2/auth"
    private let tokenURL = "https://oauth2.googleapis.com/token"
    private let scopes = "https://www.googleapis.com/auth/calendar.readonly"

    private var codeVerifier: String?
    private var callbackServer: CallbackServer?

    private init() {
        let env = Self.loadEnv()
        let overrideId = UserDefaults.standard.string(forKey: "googleOAuthClientId") ?? ""
        self.clientId = overrideId.isEmpty
            ? (env["GOOGLE_OAUTH_CLIENT_ID"] ?? "")
            : overrideId
        self.clientSecret = env["GOOGLE_OAUTH_CLIENT_SECRET"] ?? ""

        if clientId.isEmpty {
            logger.warning("No Google OAuth client ID configured")
        }
    }

    /// Loads .env file from multiple search locations
    private static func loadEnv() -> [String: String] {
        var result: [String: String] = [:]

        let searchPaths: [URL] = [
            // 1. Application Support (most reliable)
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Scribe/.env"),
            // 2. Current working directory
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".env"),
            // 3. Next to the executable
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(".env"),
            // 4. Bundle Resources (embedded by build-dmg.sh for personal builds)
            Bundle.main.resourceURL?.appendingPathComponent(".env"),
            // 5. Walk up from .build/arm64-apple-macosx/debug/ to project root
            Bundle.main.executableURL?
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent(".env"),
        ].compactMap { $0 }

        for path in searchPaths {
            guard let contents = try? String(contentsOf: path, encoding: .utf8) else {
                continue
            }
            logger.info("Loaded .env from: \(path.path)")
            for line in contents.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    result[String(parts[0])] = String(parts[1])
                }
            }
            break
        }

        if result.isEmpty {
            logger.warning("No .env file found. Searched: \(searchPaths.map(\.path).joined(separator: ", "))")
        }

        return result
    }

    /// Start the OAuth flow — opens browser for consent
    public func authorize() async throws -> GoogleTokens {
        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)
        self.codeVerifier = verifier

        let server = CallbackServer(port: 8089)
        self.callbackServer = server

        let authCode = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            server.start { code in
                cont.resume(returning: code)
            } onError: { error in
                cont.resume(throwing: error)
            }

            // Build authorization URL
            var components = URLComponents(string: authURL)!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: clientId),
                URLQueryItem(name: "redirect_uri", value: redirectURI),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: scopes),
                URLQueryItem(name: "code_challenge", value: challenge),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "consent"),
            ]

            if let url = components.url {
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(url)
                }
            }
        }

        server.stop()
        self.callbackServer = nil

        // Exchange code for tokens
        return try await exchangeCode(authCode, verifier: verifier)
    }

    /// Refresh an expired access token
    public func refreshToken(_ refreshToken: String) async throws -> GoogleTokens {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var params = [
            "client_id=\(clientId)",
            "grant_type=refresh_token",
            "refresh_token=\(refreshToken)",
        ]
        if !clientSecret.isEmpty {
            params.append("client_secret=\(clientSecret)")
        }
        let body = params.joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        return try parseTokenResponse(data, existingRefreshToken: refreshToken)
    }

    // MARK: - Private

    private func exchangeCode(_ code: String, verifier: String) async throws -> GoogleTokens {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let encodedCode = code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code

        var params = [
            "client_id=\(clientId)",
            "code=\(encodedCode)",
            "code_verifier=\(verifier)",
            "grant_type=authorization_code",
            "redirect_uri=\(redirectURI)",
        ]
        if !clientSecret.isEmpty {
            params.append("client_secret=\(clientSecret)")
        }
        let body = params.joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        logger.info("Exchanging auth code for tokens (code length: \(code.count), verifier length: \(verifier.count))")
        let (data, response) = try await URLSession.shared.data(for: request)
        let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
        logger.info("Token exchange response: HTTP \(httpStatus)")

        if let responseStr = String(data: data, encoding: .utf8) {
            logger.info("Token response body: \(responseStr)")
        }

        return try parseTokenResponse(data)
    }

    private func parseTokenResponse(_ data: Data, existingRefreshToken: String? = nil) throws -> GoogleTokens {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8) ?? "unparseable"
            logger.error("Token response not valid JSON: \(raw)")
            throw GoogleOAuthError.tokenExchangeFailed
        }

        if let error = json["error"] as? String {
            let desc = json["error_description"] as? String ?? ""
            logger.error("Google OAuth error: \(error) - \(desc)")
            throw GoogleOAuthError.tokenExchangeFailed
        }

        guard let accessToken = json["access_token"] as? String else {
            logger.error("No access_token in response: \(json.keys.joined(separator: ", "))")
            throw GoogleOAuthError.tokenExchangeFailed
        }
        let refreshToken = (json["refresh_token"] as? String) ?? existingRefreshToken
        let expiresIn = json["expires_in"] as? Int ?? 3600

        return GoogleTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
        )
    }

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        var hash = [UInt8](repeating: 0, count: 32)
        data.withUnsafeBytes { ptr in
            _ = CC_SHA256(ptr.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public struct GoogleTokens: Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date

    public var isExpired: Bool { Date() >= expiresAt }
}

public enum GoogleOAuthError: Error, LocalizedError {
    case tokenExchangeFailed
    case noRefreshToken
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .tokenExchangeFailed: return "Failed to exchange auth code for tokens"
        case .noRefreshToken: return "No refresh token available"
        case .cancelled: return "OAuth flow was cancelled"
        }
    }
}

// MARK: - Minimal callback server

private final class CallbackServer: @unchecked Sendable {
    private let port: UInt16
    private var listener: Task<Void, Never>?
    private var onCode: ((String) -> Void)?
    private var onError: ((Error) -> Void)?

    init(port: UInt16) {
        self.port = port
    }

    func start(onCode: @escaping (String) -> Void, onError: @escaping (Error) -> Void) {
        self.onCode = onCode
        self.onError = onError

        listener = Task.detached { [weak self, port] in
            guard let self else { return }
            do {
                let server = try Socket.listen(port: port)
                defer { close(server) }

                let client = accept(server, nil, nil)
                guard client >= 0 else { return }
                defer { close(client) }

                var buffer = [UInt8](repeating: 0, count: 4096)
                let bytesRead = recv(client, &buffer, buffer.count, 0)
                guard bytesRead > 0 else { return }

                let request = String(bytes: buffer[..<bytesRead], encoding: .utf8) ?? ""

                // Parse code from GET /callback?code=XXX
                if let codeRange = request.range(of: "code="),
                   let endRange = request[codeRange.upperBound...].rangeOfCharacter(from: CharacterSet(charactersIn: "& \r\n")) {
                    let code = String(request[codeRange.upperBound..<endRange.lowerBound])

                    let response = """
                        HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n<!DOCTYPE html>
                        <html>
                        <head>
                        <meta charset="utf-8">
                        <title>Scribe - Authorization Complete</title>
                        <style>
                            * { margin: 0; padding: 0; box-sizing: border-box; }
                            body {
                                font-family: -apple-system, BlinkMacSystemFont, 'SF Pro', 'Helvetica Neue', sans-serif;
                                background: linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%);
                                color: #e0e0e0;
                                display: flex;
                                justify-content: center;
                                align-items: center;
                                min-height: 100vh;
                            }
                            .card {
                                background: rgba(255,255,255,0.08);
                                backdrop-filter: blur(20px);
                                border: 1px solid rgba(255,255,255,0.12);
                                border-radius: 20px;
                                padding: 48px;
                                text-align: center;
                                max-width: 440px;
                                box-shadow: 0 8px 32px rgba(0,0,0,0.3);
                            }
                            .icon {
                                font-size: 56px;
                                margin-bottom: 20px;
                            }
                            h1 {
                                font-size: 24px;
                                font-weight: 600;
                                margin-bottom: 12px;
                                color: #ffffff;
                            }
                            p {
                                font-size: 15px;
                                color: #a0a0b0;
                                line-height: 1.5;
                                margin-bottom: 8px;
                            }
                            .countdown {
                                font-size: 13px;
                                color: #6a6a7a;
                                margin-top: 16px;
                            }
                        </style>
                        </head>
                        <body>
                            <div class="card">
                                <div class="icon">&#10003;</div>
                                <h1>Connected to Google Calendar</h1>
                                <p>Scribe can now read your upcoming meetings.</p>
                                <p class="countdown" id="cd">This tab will close in 3 seconds...</p>
                            </div>
                            <script>
                                let s = 3;
                                const el = document.getElementById('cd');
                                const t = setInterval(() => {
                                    s--;
                                    if (s <= 0) {
                                        clearInterval(t);
                                        el.textContent = 'You can close this tab now.';
                                        window.close();
                                    } else {
                                        el.textContent = 'This tab will close in ' + s + ' seconds...';
                                    }
                                }, 1000);
                            </script>
                        </body>
                        </html>
                        """
                    _ = send(client, response, response.count, 0)

                    self.onCode?(code)
                }
            } catch {
                self.onError?(error)
            }
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }
}

// Minimal socket helper
private enum Socket {
    static func listen(port: UInt16) throws -> Int32 {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { throw GoogleOAuthError.tokenExchangeFailed }

        var optval: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &optval, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(sock, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult >= 0 else {
            close(sock)
            throw GoogleOAuthError.tokenExchangeFailed
        }

        guard Darwin.listen(sock, 1) >= 0 else {
            close(sock)
            throw GoogleOAuthError.tokenExchangeFailed
        }

        return sock
    }
}

// CommonCrypto for SHA256
import CommonCrypto
