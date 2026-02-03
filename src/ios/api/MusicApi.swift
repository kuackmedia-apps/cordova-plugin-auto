import Foundation

protocol MusicApi {
    func getAlbumTracks(albumId: String, completion: @escaping (Result<AlbumTracks, Error>) -> Void)
    func getPlayListTracks(playListId: String, completion: @escaping (Result<PlaylistTracks, Error>) -> Void)
    func getArtistTracks(artistId: String, completion: @escaping (Result<ArtistTracks, Error>) -> Void)
    func getTrackUrl(trackRequest: TrackRequest, completion: @escaping (Result<TrackResponse, Error>) -> Void)
    func getTagTracks(tagId: String, lastIdAlbumTrack: String, completion: @escaping (Result<Track, Error>) -> Void)
    func getTagPlaylists(tagId: String, completion: @escaping (Result<[[String: Any]], Error>) -> Void)
    func search(text: String, limit: Int, completion: @escaping (Result<SearchResponse, Error>) -> Void)
}

class MusicApiImpl: MusicApi {
    // Use the same base URL configured in TokenInterceptor to mirror Android
    var baseURL: URL {
        if let url = URL(string: TokenInterceptor.baseUrl) {
            return url
        }
        let fallback = "https://api.prod.kuackmedia.com/api/"
        print("[MusicApi] Invalid base URL: \(TokenInterceptor.baseUrl). Falling back to \(fallback)")
        return URL(string: fallback)!
    }
    let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.protocolClasses = [TokenInterceptor.self] + (config.protocolClasses ?? [])
        self.session = URLSession(configuration: config)
        print("[MusicApi] Initialized with baseURL=\(baseURL.absoluteString)")
    }

    func getAlbumTracks(albumId: String, completion: @escaping (Result<AlbumTracks, Error>) -> Void) {
        let pathURL = baseURL.appendingPathComponent("albums").appendingPathComponent(albumId)
        var components = URLComponents(url: pathURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "limit", value: "5")]
        guard let url = components?.url else {
            completion(.failure(NSError(domain: "MusicApi", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid albums URL"])) )
            return
        }
        request(url: url, completion: completion)
    }

    func getPlayListTracks(playListId: String, completion: @escaping (Result<PlaylistTracks, Error>) -> Void) {
        let pathURL = baseURL.appendingPathComponent("playlists").appendingPathComponent(playListId)
        var components = URLComponents(url: pathURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "limit", value: "40"),
            URLQueryItem(name: "offset", value: "0")
        ]
        guard let url = components?.url else {
            completion(.failure(NSError(domain: "MusicApi", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid playlists URL"])) )
            return
        }
        request(url: url, completion: completion)
    }

    func getArtistTracks(artistId: String, completion: @escaping (Result<ArtistTracks, Error>) -> Void) {
        let pathURL = baseURL.appendingPathComponent("artists").appendingPathComponent(artistId).appendingPathComponent("tracks")
        var components = URLComponents(url: pathURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "order", value: "popularity"),
            URLQueryItem(name: "limit", value: "100")
        ]
        guard let url = components?.url else {
            completion(.failure(NSError(domain: "MusicApi", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid artists URL"])) )
            return
        }
        request(url: url, completion: completion)
    }

    func getTrackUrl(trackRequest: TrackRequest, completion: @escaping (Result<TrackResponse, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("track-url")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(trackRequest)
        } catch {
            completion(.failure(error))
            return
        }
        dataTask(request: request, completion: completion)
    }

    func getTagTracks(tagId: String, lastIdAlbumTrack: String, completion: @escaping (Result<Track, Error>) -> Void) {
        // Build URL with proper query encoding; do NOT include '?' inside a path component
        let pathURL = baseURL
            .appendingPathComponent("stations")
            .appendingPathComponent(tagId)
            .appendingPathComponent("track")
        var components = URLComponents(url: pathURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "lastIdAlbumTrack", value: lastIdAlbumTrack)]
        guard let finalURL = components?.url else {
            completion(.failure(NSError(domain: "MusicApi", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid stations URL"])) )
            return
        }
        var request = URLRequest(url: finalURL)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        dataTask(request: request, completion: completion)
    }

    func getTagPlaylists(tagId: String, completion: @escaping (Result<[[String: Any]], Error>) -> Void) {
        let pathURL = baseURL.appendingPathComponent("tags").appendingPathComponent(tagId).appendingPathComponent("playlists")
        var components = URLComponents(url: pathURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "limit", value: "30"),
            URLQueryItem(name: "offset", value: "0")
        ]
        guard let url = components?.url else {
            completion(.failure(NSError(domain: "MusicApi", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid tag playlists URL"])))
            return
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "MusicApi", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let list = json["list"] as? [[String: Any]] {
                    completion(.success(list))
                } else {
                    completion(.failure(NSError(domain: "MusicApi", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    func search(text: String, limit: Int = 30, completion: @escaping (Result<SearchResponse, Error>) -> Void) {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false) else {
            completion(.failure(NSError(domain: "MusicApi", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid base URL"])) )
            return
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components.url else {
            completion(.failure(NSError(domain: "MusicApi", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])) )
            return
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        dataTask(request: request, completion: completion)
    }

    // MARK: - Helpers
    private func request<T: Decodable>(url: URL, completion: @escaping (Result<T, Error>) -> Void) {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        dataTask(request: request, completion: completion)
    }

    private func dataTask<T: Decodable>(request: URLRequest, completion: @escaping (Result<T, Error>) -> Void) {
        print("[MusicApi] Request: \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "-")")
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(NSError(domain: "MusicApi", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }
            // Validate HTTP status code first
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                print("[MusicApi] HTTP ERROR status=\(http.statusCode) url=\(http.url?.absoluteString ?? "-")\nBody:\n\(body)")
                completion(.failure(NSError(domain: "MusicApi", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) for \(http.url?.absoluteString ?? "-")"])) )
                return
            }
            // Quick guard for HTML bodies mistakenly returned by server
            if let sniff = String(data: data.prefix(1), encoding: .utf8), sniff == "<" {
                let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                print("[MusicApi] Non-JSON body detected (starts with '<'). Skipping decode.\nBody:\n\(body)")
                completion(.failure(NSError(domain: "MusicApi", code: -3, userInfo: [NSLocalizedDescriptionKey: "Non-JSON response body"])) )
                return
            }
            do {
                let decoded = try JSONDecoder().decode(T.self, from: data)
                completion(.success(decoded))
            } catch {
                let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                print("[MusicApi][DECODE ERROR] \(error)\nResponse body: \n\(body)")
                completion(.failure(error))
            }
        }.resume()
    }
}
