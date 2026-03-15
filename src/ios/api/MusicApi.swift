import Foundation

protocol MusicApi {
    func getAlbumTracks(albumId: String, limit: Int, offset: Int, completion: @escaping (Result<AlbumTracks, Error>) -> Void)
    func getPlayListTracks(playListId: String, limit: Int, offset: Int, completion: @escaping (Result<PlaylistTracks, Error>) -> Void)
    func getArtistTracks(artistId: String, order: String, limit: Int, offset: Int, completion: @escaping (Result<ArtistTracks, Error>) -> Void)
    func getTrackUrl(trackRequest: TrackRequest, completion: @escaping (Result<TrackResponse, Error>) -> Void)
    func getRadioTracks(stationId: String, count: Int, lastIdAlbumTrack: Int64?, completion: @escaping (Result<[Track], Error>) -> Void)
    func getTagPlaylists(tagId: String, completion: @escaping (Result<[[String: Any]], Error>) -> Void)
    func search(text: String, limit: Int, completion: @escaping (Result<SearchResponse, Error>) -> Void)
    func searchTracks(text: String, limit: Int, completion: @escaping (Result<TrackResult, Error>) -> Void)
    func searchArtists(text: String, limit: Int, completion: @escaping (Result<ArtistResult, Error>) -> Void)
    func searchAlbums(text: String, limit: Int, completion: @escaping (Result<AlbumResult, Error>) -> Void)
    func searchPlaylists(text: String, limit: Int, completion: @escaping (Result<PlaylistResult, Error>) -> Void)
    func searchTags(text: String, limit: Int, completion: @escaping (Result<TagResult, Error>) -> Void)
    func getArtistAlbums(artistId: String, limit: Int, offset: Int, completion: @escaping (Result<ArtistAlbumsResponse, Error>) -> Void)
    func getArtistPlaylists(artistId: String, limit: Int, offset: Int, completion: @escaping (Result<ArtistPlaylistsResponse, Error>) -> Void)
    func getRelatedArtists(artistId: String, limit: Int, completion: @escaping (Result<RelatedArtistsResponse, Error>) -> Void)
    func getRelatedTracks(trackId: String, limit: Int, completion: @escaping (Result<ArtistTracks, Error>) -> Void)
    func getRelatedTracksByQueue(request: RelatedTracksByQueueRequest, limit: Int, completion: @escaping (Result<ArtistTracks, Error>) -> Void)
    func getPodcastEpisodes(showId: String, limit: Int, offset: Int, completion: @escaping (Result<PodcastShowResponse, Error>) -> Void)
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

    func getAlbumTracks(albumId: String, limit: Int = 15, offset: Int = 0, completion: @escaping (Result<AlbumTracks, Error>) -> Void) {
        let pathURL = baseURL.appendingPathComponent("albums").appendingPathComponent(albumId)
        var components = URLComponents(url: pathURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        guard let url = components?.url else {
            completion(.failure(NSError(domain: "MusicApi", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid albums URL"])) )
            return
        }
        request(url: url, completion: completion)
    }

    func getPlayListTracks(playListId: String, limit: Int = 15, offset: Int = 0, completion: @escaping (Result<PlaylistTracks, Error>) -> Void) {
        let pathURL = baseURL.appendingPathComponent("playlists").appendingPathComponent(playListId)
        var components = URLComponents(url: pathURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        guard let url = components?.url else {
            completion(.failure(NSError(domain: "MusicApi", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid playlists URL"])) )
            return
        }
        request(url: url, completion: completion)
    }

    func getArtistTracks(artistId: String, order: String = "popularity", limit: Int = 15, offset: Int = 0, completion: @escaping (Result<ArtistTracks, Error>) -> Void) {
        let pathURL = baseURL.appendingPathComponent("artists").appendingPathComponent(artistId).appendingPathComponent("tracks")
        var components = URLComponents(url: pathURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "order", value: order),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
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

    func getRadioTracks(stationId: String, count: Int = 15, lastIdAlbumTrack: Int64? = nil, completion: @escaping (Result<[Track], Error>) -> Void) {
        let pathURL = baseURL
            .appendingPathComponent("stations")
            .appendingPathComponent(stationId)
            .appendingPathComponent("track")
        var components = URLComponents(url: pathURL, resolvingAgainstBaseURL: false)
        var queryItems = [URLQueryItem(name: "count", value: String(count))]
        if let lastId = lastIdAlbumTrack {
            queryItems.append(URLQueryItem(name: "lastIdAlbumTrack", value: String(lastId)))
        }
        components?.queryItems = queryItems
        guard let finalURL = components?.url else {
            completion(.failure(NSError(domain: "MusicApi", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid stations URL"])) )
            return
        }
        request(url: finalURL, completion: completion)
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

    // MARK: - Type-specific search endpoints

    private func searchByType<T: Decodable>(type: String, text: String, limit: Int, completion: @escaping (Result<T, Error>) -> Void) {
        let pathURL = baseURL.appendingPathComponent("search").appendingPathComponent(type)
        guard var components = URLComponents(url: pathURL, resolvingAgainstBaseURL: false) else {
            completion(.failure(NSError(domain: "MusicApi", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid search URL"])))
            return
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components.url else {
            completion(.failure(NSError(domain: "MusicApi", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        dataTask(request: request, completion: completion)
    }

    func searchTracks(text: String, limit: Int = 10, completion: @escaping (Result<TrackResult, Error>) -> Void) {
        searchByType(type: "tracks", text: text, limit: limit, completion: completion)
    }

    func searchArtists(text: String, limit: Int = 10, completion: @escaping (Result<ArtistResult, Error>) -> Void) {
        searchByType(type: "artists", text: text, limit: limit, completion: completion)
    }

    func searchAlbums(text: String, limit: Int = 10, completion: @escaping (Result<AlbumResult, Error>) -> Void) {
        searchByType(type: "albums", text: text, limit: limit, completion: completion)
    }

    func searchPlaylists(text: String, limit: Int = 10, completion: @escaping (Result<PlaylistResult, Error>) -> Void) {
        searchByType(type: "playlists", text: text, limit: limit, completion: completion)
    }

    func searchTags(text: String, limit: Int = 10, completion: @escaping (Result<TagResult, Error>) -> Void) {
        searchByType(type: "tag", text: text, limit: limit, completion: completion)
    }

    // MARK: - New endpoints (Fase 1)

    func getArtistAlbums(artistId: String, limit: Int = 15, offset: Int = 0, completion: @escaping (Result<ArtistAlbumsResponse, Error>) -> Void) {
        let pathURL = baseURL.appendingPathComponent("artists").appendingPathComponent(artistId).appendingPathComponent("albums")
        var components = URLComponents(url: pathURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        guard let url = components?.url else {
            completion(.failure(NSError(domain: "MusicApi", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid artist albums URL"])) )
            return
        }
        request(url: url, completion: completion)
    }

    func getArtistPlaylists(artistId: String, limit: Int = 15, offset: Int = 0, completion: @escaping (Result<ArtistPlaylistsResponse, Error>) -> Void) {
        let pathURL = baseURL.appendingPathComponent("artists").appendingPathComponent(artistId).appendingPathComponent("playlists")
        var components = URLComponents(url: pathURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        guard let url = components?.url else {
            completion(.failure(NSError(domain: "MusicApi", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid artist playlists URL"])) )
            return
        }
        request(url: url, completion: completion)
    }

    func getRelatedArtists(artistId: String, limit: Int = 15, completion: @escaping (Result<RelatedArtistsResponse, Error>) -> Void) {
        let pathURL = baseURL.appendingPathComponent("artists").appendingPathComponent(artistId).appendingPathComponent("related_artists")
        var components = URLComponents(url: pathURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components?.url else {
            completion(.failure(NSError(domain: "MusicApi", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid related artists URL"])) )
            return
        }
        request(url: url, completion: completion)
    }

    func getRelatedTracks(trackId: String, limit: Int = 15, completion: @escaping (Result<ArtistTracks, Error>) -> Void) {
        let pathURL = baseURL.appendingPathComponent("tracks").appendingPathComponent(trackId).appendingPathComponent("related_tracks")
        var components = URLComponents(url: pathURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components?.url else {
            completion(.failure(NSError(domain: "MusicApi", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid related tracks URL"])) )
            return
        }
        request(url: url, completion: completion)
    }

    func getRelatedTracksByQueue(request body: RelatedTracksByQueueRequest, limit: Int = 10, completion: @escaping (Result<ArtistTracks, Error>) -> Void) {
        let pathURL = baseURL.appendingPathComponent("tracks").appendingPathComponent("related")
        var components = URLComponents(url: pathURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "limit", value: String(limit))
        ]
        guard let url = components?.url else {
            completion(.failure(NSError(domain: "MusicApi", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid related tracks by queue URL"])) )
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            completion(.failure(error))
            return
        }
        dataTask(request: request, completion: completion)
    }

    func getPodcastEpisodes(showId: String, limit: Int = 20, offset: Int = 0, completion: @escaping (Result<PodcastShowResponse, Error>) -> Void) {
        let pathURL = baseURL.appendingPathComponent("podcast").appendingPathComponent(showId)
        var components = URLComponents(url: pathURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        guard let url = components?.url else {
            completion(.failure(NSError(domain: "MusicApi", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid podcast URL"])) )
            return
        }
        request(url: url, completion: completion)
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
