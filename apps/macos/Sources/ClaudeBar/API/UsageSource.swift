import Foundation

actor UsageSource {
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let anthropicBeta = "oauth-2025-04-20"

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.httpAdditionalHeaders = ["User-Agent": "claudebar-macos/0.1"]
        self.session = URLSession(configuration: config)
    }

    func fetch() async -> UsageSnapshot {
        guard var tokens = await Keychain.shared.loadTokens() else {
            return .empty(status: .unauthenticated)
        }

        var result = await call(accessToken: tokens.accessToken)

        if case .unauthorized = result, let refresh = tokens.refreshToken {
            do {
                let refreshed = try await OAuth.refreshAccessToken(refresh)
                tokens = refreshed
                await Keychain.shared.storeTokens(refreshed)
                result = await call(accessToken: refreshed.accessToken)
            } catch {
                return .empty(status: .unauthenticated)
            }
        }

        switch result {
        case .ok(let response):
            return map(response: response)
        case .unauthorized:
            return .empty(status: .unauthenticated)
        case .rateLimited:
            return .empty(status: .rateLimited)
        case .offline:
            return .empty(status: .offline)
        }
    }

    private func map(response: UsageResponse) -> UsageSnapshot {
        UsageSnapshot(
            session: UsageBucket(
                percent: response.five_hour?.utilization ?? 0,
                resetsAt: parseDate(response.five_hour?.resets_at)
            ),
            weekly: UsageBucket(
                percent: response.seven_day?.utilization ?? 0,
                resetsAt: parseDate(response.seven_day?.resets_at)
            ),
            status: .ok,
            fetchedAt: Date()
        )
    }

    private func parseDate(_ s: String?) -> Date? {
        guard let s = s else { return nil }
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFractional.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }

    private enum CallResult {
        case ok(UsageResponse)
        case unauthorized
        case rateLimited
        case offline
    }

    private func call(accessToken: String) async -> CallResult {
        var req = URLRequest(url: Self.usageURL)
        req.httpMethod = "GET"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue(Self.anthropicBeta, forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return .offline }
            switch http.statusCode {
            case 200..<300:
                let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
                return .ok(decoded)
            case 401:
                return .unauthorized
            case 429:
                return .rateLimited
            default:
                return .offline
            }
        } catch {
            return .offline
        }
    }
}

struct UsageResponse: Decodable, Sendable {
    struct Bucket: Decodable, Sendable {
        let utilization: Double
        let resets_at: String?
    }
    let five_hour: Bucket?
    let seven_day: Bucket?
}
