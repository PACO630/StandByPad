import SwiftUI
import Photos

/// 第二頁：電子相框。上下滑動切換相簿；長按編輯可隱藏相簿。
struct PhotosPage: View {
    @Binding var editing: Bool
    let onSettings: () -> Void

    @EnvironmentObject var photos: PhotoStore
    @EnvironmentObject var settings: SettingsStore
    @State private var isEditing = false
    @State private var currentID: String?
    @State private var titleVisible = false
    @State private var hideTitle: DispatchWorkItem?

    private var albums: [PhotoStore.Album] {
        isEditing ? photos.albums : photos.albums.filter { !settings.hiddenAlbums.contains($0.id) }
    }

    private func indexBinding(_ list: [PhotoStore.Album]) -> Binding<Int> {
        Binding(get: { list.firstIndex(where: { $0.id == currentID }) ?? 0 },
                set: { i in
                    currentID = list[safe: i]?.id
                    flashTitle()
                })
    }

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            let list = albums
            let index = indexBinding(list)
            let radius: CGFloat = isEditing ? 48 : 0
            ZStack {
                Color.black
                if !photos.isAuthorized {
                    PermissionPrompt(symbol: "photo.on.rectangle.angled", title: "展示你喜愛的照片",
                                     message: "允許取用照片後，這裡會像電子相框一樣輪流播放你的相簿。",
                                     button: photos.status == .denied ? "前往設定" : "允許取用照片") {
                        photos.request()
                    }
                } else if list.isEmpty {
                    PermissionPrompt(symbol: "eye.slash", title: "沒有可顯示的相簿",
                                     message: "長按此畫面，點一下相簿右下角的眼睛圖示即可重新顯示。",
                                     button: "編輯相簿") { enterEdit() }
                } else {
                    Pager(axis: .vertical, count: list.count, index: index, effect: .stack) { i in
                        AlbumSlideshow(album: list[i], active: i == index.wrappedValue && !isEditing, showInfo: !isEditing)
                            .overlay { hiddenOverlay(list[i]) }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .scaleEffect(isEditing ? 0.78 : 1)
                    .onLongPressGesture(minimumDuration: 0.5) { enterEdit() }

                    if let album = list[safe: index.wrappedValue] {
                        Text(album.title)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .background(Capsule().fill(.ultraThinMaterial))
                            .position(x: isEditing ? W / 2 - W * 0.39 + 110 : 140, y: isEditing ? H / 2 - H * 0.39 + 44 : 60)
                            .opacity(titleVisible || isEditing ? 1 : 0)
                            .animation(.easeInOut(duration: 0.3), value: titleVisible)

                        PageDots(count: list.count, index: index.wrappedValue)
                            .position(x: isEditing ? W / 2 + W * 0.39 + 30 : W - 26, y: H / 2)
                            .opacity(titleVisible || isEditing ? 1 : 0)

                        if isEditing {
                            let hidden = settings.hiddenAlbums.contains(album.id)
                            Button { toggleHidden(album.id) } label: {
                                Image(systemName: hidden ? "eye.slash.fill" : "eye.fill")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(width: 56, height: 56)
                                    .background(Circle().fill(Color.black.opacity(0.6)))
                            }
                            .buttonStyle(PressScaleStyle())
                            .accessibilityLabel(hidden ? "顯示這個相簿" : "隱藏這個相簿")
                            .position(x: W / 2 + W * 0.39 - 48, y: H / 2 + H * 0.39 - 48)
                        }
                    }
                }
                if isEditing {
                    EditTopBar(onSettings: onSettings, onDone: exitEdit) { EmptyView() }
                        .transition(.opacity)
                }
            }
            .frame(width: W, height: H)
        }
        .onAppear {
            if settings.hasSeenWelcome { photos.start() }
            if DebugLaunch.state == "editPhotos" { isEditing = true }
        }
        .onChange(of: isEditing) { editing = $0 }
    }

    @ViewBuilder private func hiddenOverlay(_ album: PhotoStore.Album) -> some View {
        if isEditing && settings.hiddenAlbums.contains(album.id) {
            Color.black.opacity(0.55)
        }
    }

    private func toggleHidden(_ id: String) {
        withAnimation(.easeInOut(duration: 0.25)) {
            if let i = settings.hiddenAlbums.firstIndex(of: id) { settings.hiddenAlbums.remove(at: i) }
            else { settings.hiddenAlbums.append(id) }
        }
    }

    private func enterEdit() {
        guard !isEditing else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { isEditing = true }
    }

    private func exitEdit() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { isEditing = false }
        if let id = currentID, settings.hiddenAlbums.contains(id) { currentID = nil }
    }

    private func flashTitle() {
        hideTitle?.cancel()
        titleVisible = true
        let work = DispatchWorkItem { titleVisible = false }
        hideTitle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }
}

struct AlbumSlideshow: View {
    let album: PhotoStore.Album
    let active: Bool
    var showInfo = true

    @EnvironmentObject var photos: PhotoStore
    @State private var position: Int
    @State private var image: UIImage?
    @State private var imageID = UUID()
    @State private var place: String?
    @State private var date: Date?

    private let timer = Timer.publish(every: 9, on: .main, in: .common).autoconnect()

    init(album: PhotoStore.Album, active: Bool, showInfo: Bool = true) {
        self.album = album
        self.active = active
        self.showInfo = showInfo
        _position = State(initialValue: album.assets.count > 0 ? Int.random(in: 0..<album.assets.count) : 0)
    }

    var body: some View {
        GeometryReader { geo in
            let H = geo.size.height
            ZStack {
                Color.black
                if let image {
                    KenBurnsImage(image: image)
                        .id(imageID)
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .overlay(alignment: .topTrailing) {
                TimelineView(.everyMinute) { ctx in
                    Text(Fmt.clock(ctx.date))
                        .font(.system(size: H * 0.15, weight: .semibold))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.35), radius: 14)
                        .accessibilityLabel(Fmt.time(ctx.date))
                }
                .padding(.top, H * 0.05)
                .padding(.trailing, geo.size.width * 0.05)
                .opacity(showInfo ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: showInfo)
            }
            .overlay(alignment: .bottomTrailing) {
                VStack(alignment: .trailing, spacing: 4) {
                    if let place {
                        Text(place).font(.system(size: H * 0.05, weight: .bold))
                    }
                    if let date {
                        HStack(spacing: 4) {
                            Text(Fmt.fullDate(date))
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: H * 0.03, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.45), radius: 10)
                .padding(.bottom, H * 0.06)
                .padding(.trailing, geo.size.width * 0.05)
                .onTapGesture { SystemLinks.open("photos-redirect://") }
                .opacity(showInfo ? 1 : 0)
                .allowsHitTesting(showInfo)
                .animation(.easeInOut(duration: 0.25), value: showInfo)
            }
            .task(id: "\(album.id)-\(position)") { await load(size: geo.size) }
        }
        .onReceive(timer) { _ in
            guard active, album.assets.count > 1 else { return }
            position = (position + 1) % album.assets.count
        }
    }

    private func load(size: CGSize) async {
        guard album.assets.count > 0 else { return }
        let asset = album.assets.object(at: position % album.assets.count)
        let scale = UIScreen.main.scale
        let img = await photos.image(for: asset, size: CGSize(width: size.width * scale, height: size.height * scale))
        guard let img else { return }
        withAnimation(.easeInOut(duration: 1.2)) {
            image = img
            imageID = UUID()
            date = asset.creationDate
        }
        let p = await photos.place(for: asset)
        withAnimation(.easeInOut(duration: 0.4)) { place = p }
    }
}

struct KenBurnsImage: View {
    let image: UIImage
    @State private var zoom = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(zoom ? 1.1 : 1.0)
                .clipped()
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 12)) { zoom = true }
        }
    }
}
