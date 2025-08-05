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
    static var baseUrl: String = "https://your.api.base.url/"

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
        let session = URLSession(configuration: .default)
        let task = session.dataTask(with: request) { data, response, error in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                // Try to refresh token
                TokenInterceptor.refreshAuthToken { newToken in
                    if let newToken = newToken {
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
            if let data = data, let response = response {
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: data)
            }
            if let error = error {
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
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newToken = json["accessToken"] as? String,
                  let newRefreshToken = json["refreshToken"] as? String else {
                completion(nil)
                return
            }
            UserDefaults.standard.setValue("\"\(newToken)\"", forKey: "AT_TOKEN_KEY")
            UserDefaults.standard.setValue("\"\(newRefreshToken)\"", forKey: "REFRESH_TOKEN_KEY")
            completion(newToken)
        }
        task.resume()
    }
}
