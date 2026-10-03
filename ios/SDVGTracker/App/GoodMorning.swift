import Foundation
import Observation
import SDVGCore

/// The morning video: on the first launch of the morning a random video from the server
/// (/video/index.json, see make videos-deploy) plays over the whole screen, once a day.
/// It is downloaded ahead, on an earlier launch, so it starts at once and needs no network.
@MainActor @Observable
final class GoodMorning {
    /// The video plays by itself in the morning; a setting on this device, on by default.
    /// Off, nothing is downloaded ahead; the settings button still shows one.
    var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: Self.enabledKey)
            prepare()
        }
    }
    /// The video on screen.
    private(set) var playing: URL?
    /// The settings button is waiting for a download, or it failed.
    private(set) var loading = false
    private(set) var failed = false
    /// After the first video this device shows: keep them, or turn them off? Asked once.
    var askToKeep = false

    @ObservationIgnored private let baseURL: () -> String
    @ObservationIgnored private var preparing: Task<Void, Never>?

    // Per device, gone with the app: the switch, whether keeping them was asked, the file ready
    // for the next morning, the one shown last (not to repeat it) and the (logical) day it was shown.
    private static let enabledKey = "goodmorning_enabled"
    private static let askedKey = "goodmorning_asked"
    private static let nextKey = "goodmorning_next"
    private static let lastKey = "goodmorning_last"
    private static let shownKey = "goodmorning_shown_day"
    private static let dir = URL.cachesDirectory.appending(path: "goodmorning", directoryHint: .isDirectory)

    private struct Index: Decodable {
        struct Video: Decodable {
            let file: String
            let size: Int
        }
        let videos: [Video]

        /// A random video, other than the avoided ones while there are others. Only plain file
        /// names: the name becomes a path in the cache.
        func random(avoiding names: [String]) throws -> Video {
            let valid = videos.filter { !$0.file.contains("/") && !$0.file.hasPrefix(".") && $0.file.hasSuffix(".mp4") }
            guard let video = valid.filter({ !names.contains($0.file) }).randomElement() ?? valid.randomElement() else {
                throw URLError(.zeroByteResource)
            }
            return video
        }
    }

    init(baseURL: @escaping () -> String) {
        self.baseURL = baseURL
        enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    private var defaults: UserDefaults { .standard }

    /// The video ready for the next morning, if the system has not cleared it from the cache.
    private var next: URL? {
        guard let name = defaults.string(forKey: Self.nextKey) else { return nil }
        let url = Self.dir.appending(path: name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// On launch and on return to the app: plays the ready video if it is the morning and none
    /// has played today; otherwise makes sure one is ready for the next morning.
    func greet(now: LocalDateTime, settings: Settings) {
        let day = Dates.logicalDay(now, dayStartHour: settings.dayStartHour)
        guard enabled, playing == nil, Dates.partOfDay(now, settings) == .morning,
              defaults.string(forKey: Self.shownKey) != day, let next else {
            prepare()
            return
        }
        defaults.set(day, forKey: Self.shownKey)
        defaults.set(next.lastPathComponent, forKey: Self.lastKey)
        defaults.removeObject(forKey: Self.nextKey)
        playing = next
    }

    /// The settings button: a random video right now, other than the last one and tomorrow's.
    func showRandom() async {
        guard playing == nil, !loading else { return }
        loading = true
        failed = false
        defer { loading = false }
        do {
            let video = try await fetchIndex().random(avoiding: [Self.nextKey, Self.lastKey].compactMap { defaults.string(forKey: $0) })
            playing = try await download(video)
        } catch {
            print("good morning video failed:", error)
            failed = true
        }
    }

    /// The video has faded out.
    func finished() {
        playing = nil
        if enabled, !defaults.bool(forKey: Self.askedKey) {
            askToKeep = true  // tomorrow's video waits for the answer
        } else {
            prepare()
        }
    }

    /// The answer to askToKeep.
    func keep(_ keep: Bool) {
        defaults.set(true, forKey: Self.askedKey)
        askToKeep = false
        if keep { prepare() } else { enabled = false }
    }

    /// Downloads a random video for the next morning unless one is ready (or the video is off),
    /// and clears the rest of the cache.
    func prepare() {
        guard preparing == nil, !baseURL().isEmpty else { return }
        preparing = Task {
            defer { preparing = nil }
            if enabled, next == nil {
                do {
                    let video = try await fetchIndex().random(avoiding: [Self.lastKey].compactMap { defaults.string(forKey: $0) })
                    defaults.set(try await download(video).lastPathComponent, forKey: Self.nextKey)
                } catch {
                    print("good morning video failed:", error)
                }
            }
            prune()
        }
    }

    /// Keeps only the next morning's video and the one on screen.
    private func prune() {
        let keep = Set([next, playing].compactMap { $0?.lastPathComponent })
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.dir, includingPropertiesForKeys: nil)) ?? []
        for file in files where !keep.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func url(_ file: String) throws -> URL {
        guard let url = URL(string: baseURL() + "/video/" + file), url.scheme?.hasPrefix("http") == true else {
            throw URLError(.badURL)
        }
        return url
    }

    private func fetchIndex() async throws -> Index {
        let request = URLRequest(url: try url("index.json"), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(Index.self, from: data)
    }

    /// The video's file in the cache; one already there is not downloaded again.
    private func download(_ video: Index.Video) async throws -> URL {
        let target = Self.dir.appending(path: video.file)
        if (try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) == video.size { return target }
        let (temp, response) = try await URLSession.shared.download(from: try url(video.file))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let fm = FileManager.default
        try fm.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        try? fm.removeItem(at: target)
        try fm.moveItem(at: temp, to: target)
        return target
    }
}
