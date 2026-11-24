import SwiftUI

/// 從待機模式直接挑選資料庫裡的音樂（最近播放、播放列表），交給「音樂」App 播放。
struct MusicLibraryView: View {
    @EnvironmentObject var music: MusicStore
    @State private var tab = 0
    @GestureState private var dragY: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            ZStack {
                Color.black.opacity(0.55)
                    .onTapGesture { music.closeLibrary() }
                    .accessibilityLabel("關閉音樂資料庫")
                    .accessibilityAddTraits(.isButton)
                VStack(spacing: 0) {
                    header
                        .contentShape(Rectangle())
                        .gesture(DragGesture().updating($dragY) { v, s, _ in s = max(0, v.translation.height) }
                            .onEnded { v in if v.translation.height > 120 { music.closeLibrary() } })
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(width: W * 0.88, height: H * 0.86)
                .background(RoundedRectangle(cornerRadius: 40, style: .continuous).fill(Color(hex: 0x1C1C1E)))
                .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 40, y: 10)
                .offset(y: dragY)
            }
        }
        .onAppear { music.loadLibrary() }
    }

    private var header: some View {
        ZStack {
            HStack(spacing: 12) {
                AppIconView(app: .music, size: 36)
                Text("音樂").font(.system(size: 24, weight: .bold)).foregroundColor(.white)
                Spacer()
                Button { music.closeLibrary() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white.opacity(0.75))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel("關閉")
            }
            Picker("類別", selection: $tab) {
                Text("最近播放").tag(0)
                Text("播放列表").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }

    @ViewBuilder private var content: some View {
        let entries = tab == 0 ? music.recent : music.playlists
        if !music.authorized {
            PermissionPrompt(symbol: "music.note.list", title: "取用你的音樂資料庫",
                             message: "允許「待機模式」取用 Apple Music 與資料庫，就能在這裡直接挑選播放列表與最近播放的歌曲。",
                             button: "前往設定") { SystemLinks.openSettings() }
        } else if music.libraryLoading && !music.libraryLoaded {
            ProgressView().progressViewStyle(.circular).tint(.white).scaleEffect(1.4)
        } else if entries.isEmpty {
            PermissionPrompt(symbol: "music.note", title: tab == 0 ? "還沒有最近播放的音樂" : "還沒有播放列表",
                             message: "在「音樂」App 把 Apple Music 的歌曲或播放列表加入資料庫後，就會出現在這裡。",
                             button: "打開「音樂」") { SystemLinks.open("music://") }
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 210), spacing: 26)], spacing: 28) {
                    ForEach(entries) { entry in
                        Button { music.play(entry) } label: { tile(entry) }
                            .buttonStyle(PressScaleStyle())
                            .accessibilityLabel("播放 \(entry.title)，\(entry.subtitle)")
                    }
                }
                .padding(28)
            }
        }
    }

    private func tile(_ e: MusicLibraryEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                if let art = e.artwork {
                    Image(uiImage: art).resizable().scaledToFill()
                } else {
                    Color.sbFill
                    Image(systemName: tab == 0 ? "music.note" : "music.note.list")
                        .font(.system(size: 44))
                        .foregroundColor(.sbGray)
                }
            }
            .frame(width: 170, height: 170)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.black.opacity(0.55)))
                    .padding(8)
            }
            Text(e.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
            Text(e.subtitle)
                .font(.system(size: 14))
                .foregroundColor(.sbGray)
                .lineLimit(1)
        }
        .frame(width: 170)
    }
}
