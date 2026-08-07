import Foundation

/// Nature Remo Cloud API クライアント。
/// ベース URL / 認証は起点資料と同じ。レート制限ヘッダを常に読む（NFR-2）。
public struct NatureAPIClient: Sendable {

    public static let baseURL = URL(string: "https://api.nature.global/1")!

    /// AppIntent はウィジェット拡張プロセス内で短時間しか動けないため短めに切る（NFR-7）。
    public static let timeout: TimeInterval = 5

    private let token: String
    private let session: URLSession

    public init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    /// Keychain からトークンを読んで生成する。
    public static func fromKeychain() throws -> NatureAPIClient {
        NatureAPIClient(token: try TokenStore.load())
    }

    // MARK: - エラー

    public enum APIError: LocalizedError, Equatable {
        case unauthorized
        case rateLimited(resetAt: Date?)
        case http(status: Int)
        case offline
        case decoding(String)

        public var errorDescription: String? {
            switch self {
            case .unauthorized:
                return "トークンが無効です"
            case .rateLimited(let resetAt):
                if let resetAt {
                    let sec = max(0, Int(resetAt.timeIntervalSinceNow))
                    return "API 制限中（あと \(sec) 秒）"
                }
                return "API 制限中"
            case .http(let status):
                return "通信エラー (\(status))"
            case .offline:
                return "オフライン"
            case .decoding:
                return "応答を解釈できません"
            }
        }
    }

    // MARK: - 公開 API

    public func appliances() async throws -> ([Appliance], RateLimitInfo?) {
        try await get("/appliances")
    }

    public func devices() async throws -> ([Device], RateLimitInfo?) {
        try await get("/devices")
    }

    /// エアコン操作。応答は更新後の設定なので、そのまま SharedStore に書き戻せる（FR-19）。
    @discardableResult
    public func sendAircon(applianceId: String,
                           parameters: [String: String]) async throws -> (AirconSettings, RateLimitInfo?) {
        try await post("/appliances/\(applianceId)/aircon_settings", parameters: parameters)
    }

    /// ライト操作。応答ボディは使わないため破棄する。
    public func sendLight(applianceId: String, button: String) async throws -> RateLimitInfo? {
        let (_, rate) = try await postRaw("/appliances/\(applianceId)/light",
                                          parameters: ["button": button])
        return rate
    }

    /// ライト 3 ボタン（FR-17）。複数台へ**並行**送信する。
    /// 失敗した機器がある場合、その id を添えて投げ返す。
    public func sendLight(applianceIds: [String], button: String) async throws -> RateLimitInfo? {
        try await withThrowingTaskGroup(of: RateLimitInfo?.self) { group in
            for id in applianceIds {
                group.addTask { try await sendLight(applianceId: id, button: button) }
            }
            var latest: RateLimitInfo?
            for try await rate in group {
                if let rate, latest == nil || rate.remaining < latest!.remaining { latest = rate }
            }
            return latest
        }
    }

    // MARK: - 内部

    private func request(_ path: String, method: String, parameters: [String: String]?) -> URLRequest {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(path.trimmingPrefix("/").description))
        request.httpMethod = method
        request.timeoutInterval = Self.timeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let parameters {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(formEncoded(parameters).utf8)
        }
        return request
    }

    private func formEncoded(_ parameters: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return parameters
            .sorted { $0.key < $1.key }
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
    }

    private func get<T: Decodable>(_ path: String) async throws -> (T, RateLimitInfo?) {
        let (data, rate) = try await perform(request(path, method: "GET", parameters: nil))
        do {
            return (try JSONDecoder.nature.decode(T.self, from: data), rate)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    private func post<T: Decodable>(_ path: String,
                                    parameters: [String: String]) async throws -> (T, RateLimitInfo?) {
        let (data, rate) = try await perform(request(path, method: "POST", parameters: parameters))
        do {
            return (try JSONDecoder.nature.decode(T.self, from: data), rate)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    private func postRaw(_ path: String,
                         parameters: [String: String]) async throws -> (Data, RateLimitInfo?) {
        try await perform(request(path, method: "POST", parameters: parameters))
    }

    private func perform(_ request: URLRequest) async throws -> (Data, RateLimitInfo?) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .timedOut:
                throw APIError.offline
            default:
                throw APIError.offline
            }
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.offline }
        let rate = RateLimitInfo(headers: http)

        switch http.statusCode {
        case 200..<300:
            return (data, rate)
        case 401:
            throw APIError.unauthorized
        case 429:
            throw APIError.rateLimited(resetAt: rate?.resetAt)
        default:
            // ⚠️ トークンを含みうるため、レスポンスボディはエラーに載せない（FR-23）
            throw APIError.http(status: http.statusCode)
        }
    }
}

extension RateLimitInfo {
    /// HTTP/2 のためヘッダ名は小文字で返る。大文字小文字を区別せずに読む。
    init?(headers response: HTTPURLResponse) {
        func header(_ name: String) -> String? {
            response.value(forHTTPHeaderField: name)
        }
        guard let limit = header("X-Rate-Limit-Limit").flatMap(Int.init),
              let remaining = header("X-Rate-Limit-Remaining").flatMap(Int.init),
              let reset = header("X-Rate-Limit-Reset").flatMap(Double.init)
        else { return nil }
        self.init(limit: limit, remaining: remaining,
                  resetAt: Date(timeIntervalSince1970: reset))
    }
}
