import SwiftUI
import UIKit
import MediaPlayer
import EventKit
import Photos
import CoreLocation

// MARK: - 音樂（「音樂」App 的系統播放器，包含 Apple Music）

/// 資料庫裡可以直接播放的項目（播放列表或最近播放的歌曲）。
struct MusicLibraryEntry: Identifiable {
    enum Kind {
        case playlist([MPMediaItem])
        case song(MPMediaItem, queue: [MPMediaItem])
        case demo
    }
    let id: String
    let title: String
    let subtitle: String
    let artwork: UIImage?
    let kind: Kind
}

final class MusicStore: ObservableObject {
    @Published var title: String?
    @Published var artist: String?
    @Published var artwork: UIImage?
    @Published var isPlaying = false { didSet { if oldValue && !isPlaying { pausedAt = Date() } } }
    @Published var duration: TimeInterval = 0
    @Published var denied = false
    @Published private(set) var authorized = false
    /// 暫停後的時間；像 iPhone 的「正在播放」即時動態一樣，暫停後 10 分鐘內仍保留入口。
    @Published private(set) var pausedAt: Date?

    // 資料庫選歌
    @Published var showLibrary = false
    @Published private(set) var recent: [MusicLibraryEntry] = []
    @Published private(set) var playlists: [MusicLibraryEntry] = []
    @Published private(set) var libraryLoading = false
    @Published private(set) var libraryLoaded = false
    /// 從資料庫選歌後，要求根畫面打開全螢幕播放器。
    @Published var requestFullScreen = false

    private var player: MPMusicPlayerController?
    private var started = false
    private var demoAnchor = Date()
    private var demoPausedAt: TimeInterval?
    private var observers: [NSObjectProtocol] = []
    private var artworkCache: [String: UIImage] = [:]
    private var artworkLookup: String?

    var hasItem: Bool { title != nil }

    var showsActivity: Bool {
        guard hasItem else { return false }
        if isPlaying { return true }
        if let p = pausedAt { return Date().timeIntervalSince(p) < 600 }
        return false
    }

    var currentTime: TimeInterval {
        if Demo.enabled {
            if let p = demoPausedAt { return p }
            return Date().timeIntervalSince(demoAnchor).truncatingRemainder(dividingBy: max(duration, 1))
        }
        let t = player?.currentPlaybackTime ?? 0
        return t.isFinite ? t : 0
    }

    func start() {
        guard !started else { return }
        started = true
        if Demo.enabled {
            title = "示範歌曲（夜晚的光）"
            artist = "待機模式樂團"
            duration = 190
            isPlaying = true
            artwork = Demo.artwork()
            authorized = true
            demoAnchor = Date().addingTimeInterval(-28)
            return
        }
        #if targetEnvironment(simulator)
        // 模擬器沒有「音樂」App，系統播放器不可用。
        #else
        MPMediaLibrary.requestAuthorization { status in
            DispatchQueue.main.async {
                if status == .authorized {
                    self.authorized = true
                    self.attach()
                } else {
                    self.denied = true
                }
            }
        }
        #endif
    }

    private func attach() {
        let p = MPMusicPlayerController.systemMusicPlayer
        player = p
        p.beginGeneratingPlaybackNotifications()
        let nc = NotificationCenter.default
        for name in [Notification.Name.MPMusicPlayerControllerNowPlayingItemDidChange,
                     .MPMusicPlayerControllerPlaybackStateDidChange] {
            observers.append(nc.addObserver(forName: name, object: p, queue: .main) { [weak self] _ in self?.refresh() })
        }
        observers.append(nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        observers.append(nc.addObserver(forName: .MPMediaLibraryDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.libraryLoaded = false
        })
        MPMediaLibrary.default().beginGeneratingLibraryChangeNotifications()
        refresh()
    }

    func refresh() {
        guard let p = player else { return }
        let item = p.nowPlayingItem
        let newTitle = item?.title
        let newArtist = item?.artist ?? item?.albumArtist
        let changed = newTitle != title || newArtist != artist
        title = newTitle
        artist = newArtist
        duration = item?.playbackDuration ?? 0
        if let img = item?.artwork?.image(at: CGSize(width: 600, height: 600)), img.size.width > 1 {
            artwork = img
        } else if changed || artwork == nil {
            artwork = nil
            fetchArtworkFallback(title: newTitle, artist: newArtist)
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { isPlaying = p.playbackState == .playing }
    }

    /// Apple Music 串流歌曲（未加入資料庫）系統常不提供封面：改用歌名與歌手查 iTunes 搜尋 API 取得封面。
    private func fetchArtworkFallback(title: String?, artist: String?) {
        guard let title, !title.isEmpty else { return }
        let key = "\(title)|\(artist ?? "")"
        if let cached = artworkCache[key] { artwork = cached; return }
        guard artworkLookup != key else { return }
        artworkLookup = key
        var comps = URLComponents(string: "https://itunes.apple.com/search")!
        let region = Locale.current.regionCode ?? "TW"
        comps.queryItems = [
            URLQueryItem(name: "term", value: [title, artist ?? ""].joined(separator: " ")),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "country", value: region),
        ]
        guard let url = comps.url else { return }
        Task {
            defer { DispatchQueue.main.async { if self.artworkLookup == key { self.artworkLookup = nil } } }
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let result = try? JSONDecoder().decode(ITunesSearch.self, from: data),
                  let small = result.results.first?.artworkUrl100,
                  let big = URL(string: small.replacingOccurrences(of: "100x100bb", with: "600x600bb")),
                  let (imgData, _) = try? await URLSession.shared.data(from: big),
                  let img = UIImage(data: imgData) else { return }
            await MainActor.run {
                self.artworkCache[key] = img
                if "\(self.title ?? "")|\(self.artist ?? "")" == key {
                    withAnimation(.easeInOut(duration: 0.4)) { self.artwork = img }
                }
            }
        }
    }

    // MARK: 資料庫

    func openLibrary() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { showLibrary = true }
        loadLibrary()
    }

    func closeLibrary() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) { showLibrary = false }
    }

    func loadLibrary() {
        guard !libraryLoaded, !libraryLoading else { return }
        if Demo.enabled {
            let names = [("深夜電台", "最近播放"), ("清晨咖啡", "播放列表"), ("雨天散步", "最近播放"),
                         ("城市燈火", "播放列表"), ("海邊的風", "最近播放"), ("專注時刻", "播放列表")]
            let entries = names.enumerated().map { i, n in
                MusicLibraryEntry(id: "demo\(i)", title: n.0, subtitle: n.1 == "播放列表" ? "\(12 + i * 3) 首歌曲" : "待機模式樂團",
                                  artwork: Demo.artwork(hue: Double(i) / Double(names.count)), kind: .demo)
            }
            recent = entries.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
            playlists = entries.enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
            libraryLoaded = true
            return
        }
        guard authorized else { return }
        libraryLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let thumb = CGSize(width: 300, height: 300)
            let songs = MPMediaQuery.songs().items ?? []
            var played = songs.filter { $0.lastPlayedDate != nil }
                .sorted { ($0.lastPlayedDate ?? .distantPast) > ($1.lastPlayedDate ?? .distantPast) }
            if played.isEmpty {
                played = songs.sorted { $0.dateAdded > $1.dateAdded }
            }
            let recentItems = Array(played.prefix(40))
            let recent = recentItems.map { item in
                MusicLibraryEntry(id: "s\(item.persistentID)", title: item.title ?? "未知歌曲",
                                  subtitle: item.artist ?? item.albumTitle ?? "",
                                  artwork: item.artwork?.image(at: thumb), kind: .song(item, queue: recentItems))
            }
            let lists = (MPMediaQuery.playlists().collections as? [MPMediaPlaylist]) ?? []
            let playlists = lists.filter { !$0.items.isEmpty }.map { pl in
                MusicLibraryEntry(id: "p\(pl.persistentID)", title: pl.name ?? "播放列表",
                                  subtitle: "\(pl.count) 首歌曲",
                                  artwork: (pl.representativeItem ?? pl.items.first)?.artwork?.image(at: thumb),
                                  kind: .playlist(pl.items))
            }
            DispatchQueue.main.async {
                self.recent = recent
                self.playlists = playlists
                self.libraryLoading = false
                self.libraryLoaded = true
            }
        }
    }

    func play(_ entry: MusicLibraryEntry) {
        switch entry.kind {
        case .demo:
            title = entry.title
            artist = "待機模式樂團"
            artwork = entry.artwork
            demoAnchor = Date(); demoPausedAt = nil
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { isPlaying = true }
        case let .playlist(items):
            guard let p = player, !items.isEmpty else { return }
            p.setQueue(with: MPMediaItemCollection(items: items))
            p.play()
        case let .song(item, queue):
            guard let p = player else { return }
            p.setQueue(with: MPMediaItemCollection(items: queue.isEmpty ? [item] : queue))
            p.nowPlayingItem = item
            p.play()
        }
        closeLibrary()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.requestFullScreen = true }
    }

    func togglePlay() {
        if Demo.enabled {
            if isPlaying { demoPausedAt = currentTime } else {
                demoAnchor = Date().addingTimeInterval(-(demoPausedAt ?? 0)); demoPausedAt = nil
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isPlaying.toggle() }
            return
        }
        guard let p = player else { SystemLinks.open("music://"); return }
        if p.nowPlayingItem == nil { openLibrary(); return }
        if p.playbackState == .playing { p.pause() } else { p.play() }
    }

    func next() {
        if Demo.enabled { demoAnchor = Date(); demoPausedAt = nil; return }
        player?.skipToNextItem()
    }

    func previous() {
        if Demo.enabled { demoAnchor = Date(); demoPausedAt = nil; return }
        guard let p = player else { return }
        if p.currentPlaybackTime > 3 { p.skipToBeginning() } else { p.skipToPreviousItem() }
    }
}

private struct ITunesSearch: Decodable {
    struct Item: Decodable { let artworkUrl100: String? }
    let results: [Item]
}

// MARK: - 行事曆

final class CalendarStore: ObservableObject {
    @Published var events: [EKEvent] = []
    @Published var authorized = false
    @Published var denied = false

    private let store = EKEventStore()
    private var requested = false

    var nextEventDate: Date? { events.first(where: { !$0.isAllDay })?.startDate }

    func requestIfNeeded() {
        guard !requested else { return }
        requested = true
        if Demo.enabled {
            // 示範資料：三個今天稍後的行程（只在 -demo 啟動參數下出現）。
            let now = Date()
            let samples: [(String, Double, Double, CGColor)] = [
                ("晨間會議", 1, 1.5, UIColor.systemBlue.cgColor),
                ("牙醫回診", 3, 4, UIColor.systemOrange.cgColor),
                ("和朋友吃晚餐", 6, 8, UIColor.systemGreen.cgColor),
            ]
            events = samples.map { title, start, end, color in
                let e = EKEvent(eventStore: store)
                e.title = title
                e.startDate = now.addingTimeInterval(start * 3600)
                e.endDate = now.addingTimeInterval(end * 3600)
                let cal = EKCalendar(for: .event, eventStore: store)
                cal.cgColor = color
                e.calendar = cal
                return e
            }
            authorized = true
            return
        }
        let done: (Bool, Error?) -> Void = { ok, _ in
            DispatchQueue.main.async {
                self.authorized = ok
                self.denied = !ok
                self.fetch()
            }
        }
        if #available(iOS 17.0, *) {
            store.requestFullAccessToEvents(completion: done)
        } else {
            store.requestAccess(to: .event, completion: done)
        }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.fetch()
        }
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in self?.fetch() }
    }

    func fetch() {
        guard authorized else { return }
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: now)) ?? now
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-1800), end: end, calendars: nil)
        events = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
    }
}

// MARK: - 照片

final class PhotoStore: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    struct Album: Identifiable {
        let id: String
        let title: String
        let assets: PHFetchResult<PHAsset>
    }

    @Published var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var albums: [Album] = []

    private let manager = PHCachingImageManager()
    private let geocoder = CLGeocoder()
    private var placeCache: [String: String] = [:]
    private var registered = false

    var isAuthorized: Bool { status == .authorized || status == .limited }

    func start() {
        if isAuthorized { reload() }
    }

    func request() {
        if status == .denied || status == .restricted { SystemLinks.openSettings(); return }
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { s in
            DispatchQueue.main.async {
                self.status = s
                self.reload()
            }
        }
    }

    func reload() {
        guard isAuthorized else { return }
        if !registered { PHPhotoLibrary.shared().register(self); registered = true }
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        var result: [Album] = []
        func add(_ c: PHAssetCollection, title: String? = nil) {
            let a = PHAsset.fetchAssets(in: c, options: opts)
            if a.count > 0 {
                result.append(Album(id: c.localIdentifier, title: title ?? c.localizedTitle ?? "相簿", assets: a))
            }
        }
        if let fav = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumFavorites, options: nil).firstObject {
            add(fav, title: "精選照片")
        }
        if let lib = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumUserLibrary, options: nil).firstObject {
            add(lib, title: "最近項目")
        }
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
            .enumerateObjects { c, _, _ in add(c) }
        albums = result
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async { self.reload() }
    }

    func image(for asset: PHAsset, size: CGSize) async -> UIImage? {
        await withCheckedContinuation { cont in
            let o = PHImageRequestOptions()
            o.deliveryMode = .highQualityFormat
            o.isNetworkAccessAllowed = true
            o.resizeMode = .fast
            manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: o) { img, _ in
                cont.resume(returning: img)
            }
        }
    }

    func place(for asset: PHAsset) async -> String? {
        guard let loc = asset.location else { return nil }
        let key = String(format: "%.2f,%.2f", loc.coordinate.latitude, loc.coordinate.longitude)
        if let p = placeCache[key] { return p }
        let marks = try? await geocoder.reverseGeocodeLocation(loc, preferredLocale: Fmt.locale)
        let name = marks?.first.flatMap { $0.subLocality ?? $0.locality ?? $0.name }
        if let name { placeCache[key] = name }
        return name
    }
}
