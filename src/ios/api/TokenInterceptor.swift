import Foundation

class TokenInterceptor: URLProtocol {
    static var accessToken: String? {
        get { UserDefaults.standard.string(forKey: "AT_TOKEN_KEY")?.replacingOccurrences(of: "\"", with: "") }
        set { UserDefaults.standard.setValue(newValue, forKey: "AT_TOKEN_KEY") }
    }
    static var refreshToken: String? {
        get { UserDefaults.standard.string(forKey: "REFRESH_TOKEN_KEY")?.replacingOccurrences(of: "\"", with: "") }
        set { UserDefaults.standard.setValue(newValue, forKey: "REFRESH_TOKEN_KEY") }
    }
    static var appKuackCode: String? {
        get { UserDefaults.standard.string(forKey: "APP_KUACK_CODE")?.replacingOccurrences(of: "\"", with: "") }
        set { UserDefaults.standard.setValue(newValue, forKey: "APP_KUACK_CODE") }
    }
    static var expirationAt: String? {
        get { UserDefaults.standard.string(forKey: "AT_EXP_TIME_KEY")?.replacingOccurrences(of: "\"", with: "") }
        set { UserDefaults.standard.setValue(newValue, forKey: "AT_EXP_TIME_KEY") }
    }
    // Read API base URL from UserDefaults (key: API_URL) with safe fallback and normalized trailing slash
    static var baseUrl: String {
        let defaultBase = "https://api.prod.kuackmedia.com/api"
        if let raw = UserDefaults.standard.string(forKey: "API_URL")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            // Strip any accidental quotes stored by the host app
            let unquoted = raw.replacingOccurrences(of: "\"", with: "")
            let normalized = unquoted.hasSuffix("/") ? unquoted : unquoted + "/"
            return normalized
        }
        return defaultBase + "/"
    }

    override class func canInit(with request: URLRequest) -> Bool {
        // Intercept all requests
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        var request = self.request
        if let accessToken = TokenInterceptor.accessToken {
            var headers = request.allHTTPHeaderFields ?? [:]
            headers["Authorization"] = "Bearer \(accessToken)"
            headers["X-KUACK-APP"] = TokenInterceptor.appKuackCode ?? ""
            headers["Content-Type"] = "application/json"
            request.allHTTPHeaderFields = headers
        }
        // Diagnostics for outgoing request
        let authHeaderPreview = request.allHTTPHeaderFields?["Authorization"]?.isEmpty == false ? "present" : "missing"
        let appHeader = request.allHTTPHeaderFields?["X-KUACK-APP"] ?? "<nil>"
        print("[TokenInterceptor] -> \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "-") auth=\(authHeaderPreview) app=\(appHeader) baseUrl=\(TokenInterceptor.baseUrl)")
        // Verbose request logging similar to Android's HttpLoggingInterceptor(Level.BODY)
        if let headers = request.allHTTPHeaderFields { print("[TokenInterceptor][REQ HEADERS] \(headers)") }
        if let body = request.httpBody, body.count > 0 {
            let preview = String(data: body, encoding: .utf8) ?? "<non-utf8>"
            print("[TokenInterceptor][REQ BODY] \(preview)")
        }
        
        let session = URLSession(configuration: .default)
        let task = session.dataTask(with: request) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                print("[TokenInterceptor][401] Unauthorized. Attempting token refresh...")
                // Try to refresh token
                TokenInterceptor.refreshAuthToken { newToken in
                    if let newToken = newToken {
                        print("[TokenInterceptor] Refresh success. Retrying original request with new token.")
                        var newRequest = request
                        var headers = newRequest.allHTTPHeaderFields ?? [:]
                        headers["Authorization"] = "Bearer \(newToken)"
                        newRequest.allHTTPHeaderFields = headers
                        let retryTask = session.dataTask(with: newRequest) { data, response, error in
                            if let data = data, let response = response {
                                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                                self.client?.urlProtocol(self, didLoad: data)
                            }
                            if let error = error {
                                self.client?.urlProtocol(self, didFailWithError: error)
                            }
                            self.client?.urlProtocolDidFinishLoading(self)
                        }
                        retryTask.resume()
                    } else {
                        print("[TokenInterceptor][ERROR] Refresh failed. Returning original 401 response.")
                        if let data = data, let response = response {
                            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                            self.client?.urlProtocol(self, didLoad: data)
                        }
                        if let error = error {
                            self.client?.urlProtocol(self, didFailWithError: error)
                        }
                        self.client?.urlProtocolDidFinishLoading(self)
                    }
                }
                return
            }
            if let http = response as? HTTPURLResponse {
                print("[TokenInterceptor] <- status=\(http.statusCode) for \(request.url?.absoluteString ?? "-")")
                // On non-2xx, emit detailed diagnostics
                if !(200...299).contains(http.statusCode) {
                    if let headers = http.allHeaderFields as? [String: Any] {
                        print("[TokenInterceptor][RESP HEADERS] \(headers)")
                    }
                    if let data = data {
                        let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                        print("[TokenInterceptor][RESP BODY] \(body)")
                    }
                }
            }
            if let data = data, let response = response {
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data)
            }
            if let error = error {
                print("[TokenInterceptor][ERROR] \(error.localizedDescription)")
                self.client?.urlProtocol(self, didFailWithError: error)
            }
            self.client?.urlProtocolDidFinishLoading(self)
        }
        task.resume()
    }

    override func stopLoading() {}

    static func refreshAuthToken(completion: @escaping (String?) -> Void) {
        guard let refreshToken = TokenInterceptor.refreshToken, let appKuackCode = TokenInterceptor.appKuackCode else {
            completion(nil)
            return
        }
        let url = URL(string: "\(baseUrl)auth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(appKuackCode, forHTTPHeaderField: "X-KUACK-APP")
        let body: [String: Any] = [
            "grantType": "refresh_token",
            "token": refreshToken
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let session = URLSession(configuration: .default)
        let task = session.dataTask(with: request) { data, response, error in
            if let http = response as? HTTPURLResponse {
                print("[TokenInterceptor] Refresh response status=\(http.statusCode)")
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newToken = json["accessToken"] as? String,
                  let newRefreshToken = json["refreshToken"] as? String else {
                let preview = data.flatMap { String(data: $0, encoding: .utf8) } ?? "<no-body>"
                print("[TokenInterceptor][ERROR] Invalid refresh response. body=\(preview.prefix(160))")
                completion(nil)
                return
            }
            UserDefaults.standard.setValue("\"\(newToken)\"", forKey: "AT_TOKEN_KEY")
            UserDefaults.standard.setValue("\"\(newRefreshToken)\"", forKey: "REFRESH_TOKEN_KEY")
            print("[TokenInterceptor] Stored new access/refresh tokens")
            completion(newToken)
        }
        task.resume()
    }
}
