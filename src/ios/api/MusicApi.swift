import Foundation

protocol MusicApi {
    func getAlbumTracks(albumId: String, completion: @escaping (Result<AlbumTracks, Error>) -> Void)
    func getPlayListTracks(playListId: String, completion: @escaping (Result<PlaylistTracks, Error>) -> Void)
    func getArtistTracks(artistId: String, completion: @escaping (Result<ArtistTracks, Error>) -> Void)
    func getTrackUrl(trackRequest: TrackRequest, completion: @escaping (Result<TrackResponse, Error>) -> Void)
    func getTagTracks(tagId: String, lastIdAlbumTrack: String, completion: @escaping (Result<Track, Error>) -> Void)
    func search(text: String, limit: Int, completion: @escaping (Result<SearchResponse, Error>) -> Void)
}

@objc(MusicApiImpl)
class MusicApiImpl: MusicApi {
    let baseURL = URL(string: "https://your.api.base.url/")!
    let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.protocolClasses = [TokenInterceptor.self] + (config.protocolClasses ?? [])
        self.session = URLSession(configuration: config)
    } 

    func getAlbumTracks(albumId: String, completion: @escaping (Result<AlbumTracks, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("albums/\(albumId)?limit=100")
        request(url: url, completion: completion)
    }

    func getPlayListTracks(playListId: String, completion: @escaping (Result<PlaylistTracks, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("playlists/\(playListId)?limit=100&offset=0")
        request(url: url, completion: completion)
    }

    func getArtistTracks(artistId: String, completion: @escaping (Result<ArtistTracks, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("artists/\(artistId)/tracks?limit=100")
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
        let url = baseURL.appendingPathComponent("stations/\(tagId)/track?lastIdAlbumTrack=\(lastIdAlbumTrack)")
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        dataTask(request: request, completion: completion)
    }

    func search(text: String, limit: Int = 30, completion: @escaping (Result<SearchResponse, Error>) -> Void) {
        var components = URLComponents(url: baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
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

    // MARK: - Helpers
    private func request<T: Decodable>(url: URL, completion: @escaping (Result<T, Error>) -> Void) {
        let request = URLRequest(url: url)
        dataTask(request: request, completion: completion)
    }

    private func dataTask<T: Decodable>(request: URLRequest, completion: @escaping (Result<T, Error>) -> Void) {
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
                let decoded = try JSONDecoder().decode(T.self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}
