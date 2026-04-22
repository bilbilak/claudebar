import Foundation
import CryptoKit
import Network
import Security

enum OAuthError: LocalizedError {
    case missingAccessToken
    case stateMismatch
    case callbackMissingCode
    case providerError(String)
    case tokenEndpoint(status: Int, body: String)
    case signInTimedOut
    case cancelled
    case listenerFailure(String)

    var errorDescription: String? {
        switch self {
        case .missingAccessToken: return "Token response did not include an access_token."
        case .stateMismatch: return "OAuth state mismatch."
        case .callbackMissingCode: return "OAuth callback did not include a code."
        case .providerError(let s): return "Provider returned error: \(s)"
        case .tokenEndpoint(let status, let body): return "Token endpoint returned \(status): \(body)"
        case .signInTimedOut: return "Sign-in timed out."
        case .cancelled: return "Sign-in cancelled."
        case .listenerFailure(let s): return "Loopback listener failed: \(s)"
        }
    }
}

enum OAuth {
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let authorizeURL = URL(string: "https://claude.ai/oauth/authorize")!
    static let tokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    static let scopes = "user:inference user:profile"
    static let loginTimeout: TimeInterval = 300

    struct LoginFlow: Sendable {
        let authorizeURL: URL
        let result: @Sendable () async throws -> TokenSet
        let cancel: @Sendable () -> Void
    }

    static func startLoginFlow() throws -> LoginFlow {
        let verifier = pkceVerifier()
        let challenge = pkceChallenge(from: verifier)
        let state = randomBase64URL(byteCount: 24)
        let server = try LoopbackServer(expectedState: state)
        let port = try server.start()
        let redirectURI = "http://localhost:\(port)/callback"

        var comps = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        let url = comps.url!

        let serverRef = server
        let result: @Sendable () async throws -> TokenSet = {
            defer { serverRef.stop() }
            let callback = try await serverRef.awaitCallback(timeout: loginTimeout)
            var body: [String: String] = [
                "grant_type": "authorization_code",
                "code": callback.code,
                "client_id": clientID,
                "redirect_uri": redirectURI,
                "code_verifier": verifier,
            ]
            if let s = callback.state { body["state"] = s }
            return try await exchange(body: body)
        }

        let cancel: @Sendable () -> Void = {
            serverRef.cancelWithError(OAuthError.cancelled)
        }

        return LoginFlow(authorizeURL: url, result: result, cancel: cancel)
    }

    static func refreshAccessToken(_ refreshToken: String) async throws -> TokenSet {
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ]
        return try await exchange(body: body)
    }

    private static func exchange(body: [String: String]) async throws -> TokenSet {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw OAuthError.tokenEndpoint(status: -1, body: "no response")
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        guard (200..<300).contains(http.statusCode) else {
            throw OAuthError.tokenEndpoint(status: http.statusCode, body: text)
        }
        return try parseTokenResponse(data)
    }

    private static func parseTokenResponse(_ data: Data) throws -> TokenSet {
        struct TR: Decodable {
            let access_token: String?
            let refresh_token: String?
            let expires_in: Int?
        }
        let tr = try JSONDecoder().decode(TR.self, from: data)
        guard let access = tr.access_token else {
            throw OAuthError.missingAccessToken
        }
        let expiresAt: Int64? = tr.expires_in.map { Int64(Date().timeIntervalSince1970) + Int64($0) }
        return TokenSet(accessToken: access, refreshToken: tr.refresh_token, expiresAt: expiresAt)
    }

    private static func pkceVerifier() -> String {
        let bytes = randomBytes(32)
        return base64URL(Data(bytes))
    }

    private static func pkceChallenge(from verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(digest))
    }

    private static func randomBase64URL(byteCount: Int) -> String {
        base64URL(Data(randomBytes(byteCount)))
    }

    private static func randomBytes(_ count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return bytes
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Loopback HTTP listener for OAuth redirect

final class LoopbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let expectedState: String
    private let queue = DispatchQueue(label: "org.bilbilak.claudebar.loopback")
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Callback, Error>?
    private var completed = false

    struct Callback: Sendable {
        let code: String
        let state: String?
    }

    init(expectedState: String) throws {
        self.expectedState = expectedState
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.acceptLocalOnly = true
        self.listener = try NWListener(using: params, on: .any)
    }

    /// Starts the listener and returns the bound port once ready.
    func start() throws -> UInt16 {
        let group = DispatchGroup()
        group.enter()
        var resolvedPort: UInt16?
        var resolvedError: Error?

        listener.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                if let port = self.listener.port?.rawValue {
                    resolvedPort = port
                } else {
                    resolvedError = OAuthError.listenerFailure("no port after ready")
                }
                group.leave()
            case .failed(let err):
                resolvedError = err
                group.leave()
            case .cancelled:
                break
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
        listener.start(queue: queue)

        let waited = group.wait(timeout: .now() + 5)
        guard waited == .success else {
            listener.cancel()
            throw OAuthError.listenerFailure("listener did not reach ready state")
        }
        if let err = resolvedError {
            listener.cancel()
            throw err
        }
        guard let port = resolvedPort else {
            listener.cancel()
            throw OAuthError.listenerFailure("no port")
        }
        return port
    }

    func awaitCallback(timeout: TimeInterval) async throws -> Callback {
        return try await withCheckedThrowingContinuation { cont in
            lock.lock()
            if completed {
                lock.unlock()
                cont.resume(throwing: OAuthError.cancelled)
                return
            }
            continuation = cont
            lock.unlock()

            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish(.failure(OAuthError.signInTimedOut))
            }
        }
    }

    func stop() {
        listener.cancel()
    }

    func cancelWithError(_ error: Error) {
        finish(.failure(error))
        listener.cancel()
    }

    // MARK: - Connection handling

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, _ in
            guard let self = self else { conn.cancel(); return }
            guard let data = data, let raw = String(data: data, encoding: .utf8) else {
                self.respond(conn, status: "400 Bad Request", body: "Bad request.")
                return
            }
            self.processRequest(raw, connection: conn)
        }
    }

    private func processRequest(_ raw: String, connection conn: NWConnection) {
        guard let firstLine = raw.split(separator: "\r\n", maxSplits: 1, omittingEmptySubsequences: false).first else {
            respond(conn, status: "400 Bad Request", body: "Bad request.")
            return
        }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            respond(conn, status: "400 Bad Request", body: "Bad request.")
            return
        }
        let target = String(parts[1])
        guard target.hasPrefix("/callback") else {
            respond(conn, status: "404 Not Found", body: "Not found.")
            return
        }
        let queryString: String
        if let q = target.firstIndex(of: "?") {
            queryString = String(target[target.index(after: q)...])
        } else {
            queryString = ""
        }
        let params = parseQuery(queryString)

        if let err = params["error"] {
            let desc = params["error_description"] ?? ""
            respond(conn, status: "400 Bad Request", body: "Sign-in failed: \(err). \(desc)")
            finish(.failure(OAuthError.providerError("\(err) \(desc)".trimmingCharacters(in: .whitespaces))))
            return
        }

        guard let rawCode = params["code"] else {
            respond(conn, status: "400 Bad Request", body: "Missing authorization code.")
            finish(.failure(OAuthError.callbackMissingCode))
            return
        }

        var code = rawCode
        var returnedState = params["state"]
        if let hashIdx = rawCode.firstIndex(of: "#") {
            code = String(rawCode[rawCode.startIndex..<hashIdx])
            if returnedState == nil {
                returnedState = String(rawCode[rawCode.index(after: hashIdx)...])
            }
        }

        if let rs = returnedState, rs != expectedState {
            respond(conn, status: "400 Bad Request", body: "State mismatch.")
            finish(.failure(OAuthError.stateMismatch))
            return
        }

        respond(conn, status: "200 OK", body: "Signed in. You can close this tab and return to ClaudeBar.")
        finish(.success(Callback(code: code, state: returnedState)))
    }

    private func respond(_ conn: NWConnection, status: String, body message: String) {
        let escaped = message
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><title>ClaudeBar</title>
        <style>body{font-family:-apple-system,system-ui,sans-serif;padding:48px;max-width:480px;margin:auto;color:#222}</style>
        </head><body><h2>ClaudeBar</h2><p>\(escaped)</p></body></html>
        """
        guard let bodyData = html.data(using: .utf8) else { conn.cancel(); return }
        let headers = """
        HTTP/1.1 \(status)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(bodyData.count)\r
        Connection: close\r
        \r

        """
        var payload = Data()
        payload.append(headers.data(using: .utf8) ?? Data())
        payload.append(bodyData)
        conn.send(content: payload, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    private func finish(_ result: Result<Callback, Error>) {
        lock.lock()
        guard !completed, let cont = continuation else {
            lock.unlock()
            return
        }
        completed = true
        continuation = nil
        lock.unlock()
        switch result {
        case .success(let v): cont.resume(returning: v)
        case .failure(let e): cont.resume(throwing: e)
        }
    }

    private func parseQuery(_ s: String) -> [String: String] {
        var out: [String: String] = [:]
        for pair in s.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(kv[0]).removingPercentEncoding ?? String(kv[0])
            let value: String
            if kv.count > 1 {
                value = String(kv[1]).removingPercentEncoding ?? String(kv[1])
            } else {
                value = ""
            }
            out[key] = value
        }
        return out
    }
}
