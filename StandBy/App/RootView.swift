import SwiftUI
import UIKit

struct StandByRootView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var night: NightController
    @EnvironmentObject var alarm: AlarmController
    @EnvironmentObject var music: MusicStore
    @EnvironmentObject var weather: WeatherStore
    @EnvironmentObject var photos: PhotoStore
    @EnvironmentObject var battery: BatteryStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var editing = false
    @State private var showSettings = false
    @State private var musicFull = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black

            Pager(axis: .horizontal, count: 3, index: $settings.page, enabled: !editing && !musicFull) { i in
                page(i)
            }
            .blur(radius: settings.hasSeenWelcome ? 0 : 30)
            .opacity(musicFull ? 0 : 1)
            .scaleEffect(musicFull ? 0.94 : 1)

            if music.showsActivity && !editing && !musicFull && !music.showLibrary && settings.hasSeenWelcome {
                NowPlayingPill(playing: music.isPlaying)
                    .onTapGesture { openMusic() }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 16)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }

            VolumeHUD()
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 70)
                .zIndex(6)

            ChargingIndicator()
                .opacity(editing || musicFull || music.showLibrary ? 0 : 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(30)
                .allowsHitTesting(false)

            if musicFull {
                MusicFullScreen(onClose: closeMusic)
                    .scrollModal { t, v, _ in if abs(t) > 110 || abs(v) > 700 { closeMusic() } }
                    .transition(.scale(scale: 0.15, anchor: .top).combined(with: .opacity))
                    .zIndex(2)
            }

            if music.showLibrary {
                MusicLibraryView()
                    .scrollModal()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2.5)
            }

            if !settings.hasSeenWelcome {
                WelcomeOverlay(onClose: closeWelcome)
                .scrollModal(axis: .horizontal) { t, v, _ in if abs(t) > 60 || abs(v) > 500 { closeWelcome() } }
                .transition(.opacity)
                .zIndex(3)
            }

            if alarm.ringing {
                AlarmRingingView()
                    .scrollModal()
                    .transition(.opacity)
                    .zIndex(4)
            }
        }
        .modifier(NightTint(active: night.isNight))
        .overlay {
            Color.black
                .opacity(night.sleeping ? 1 : 0)
                .allowsHitTesting(night.sleeping)
                .onTapGesture { night.touch() }
        }
        .background(TouchObserver { night.touch() })
        .background(ScrollRouterInstaller())
        .background(HiddenSystemVolume().frame(width: 1, height: 1))
        .background(KeyboardCatcher(
            onOption: toggleMusicInterface,
            onVolume: { VolumeController.shared.step($0, showHUD: !musicFull) },
            onTrack: { dir in
                guard music.hasItem else { return }
                if dir > 0 { music.next() } else { music.previous() }
            }))
        .ignoresSafeArea()
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .scrollModal()
                .environmentObject(settings)
                .environmentObject(weather)
                .environmentObject(photos)
        }
        .onReceive(ticker) { now in
            // 執行期間永不休眠：系統在某些情況（例如權限視窗、回到前景）會重設，所以每秒確認一次。
            if !UIApplication.shared.isIdleTimerDisabled { UIApplication.shared.isIdleTimerDisabled = true }
            night.tick(now, settings: settings)
            alarm.tick(now, settings: settings)
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            VolumeController.shared.start()
            if settings.hasSeenWelcome { startServices() }
            alarm.reschedule(settings)
            if DebugLaunch.state == "music" { musicFull = true }
            if DebugLaunch.state == "settings" { showSettings = true }
            if DebugLaunch.state == "library" { music.openLibrary() }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                UIApplication.shared.isIdleTimerDisabled = true
                weather.refresh()
            } else {
                night.restoreBrightness()
            }
        }
        .onChange(of: settings.alarmEnabled) { _ in alarm.reschedule(settings) }
        .onChange(of: settings.alarmMinutes) { _ in alarm.reschedule(settings) }
        .onChange(of: music.hasItem) { has in if !has && musicFull { closeMusic() } }
        .onChange(of: music.requestFullScreen) { want in
            guard want else { return }
            music.requestFullScreen = false
            if !editing { openMusic() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }

    @ViewBuilder private func page(_ i: Int) -> some View {
        switch i {
        case 0: WidgetsPage(editing: $editing, onSettings: { showSettings = true })
        case 1: PhotosPage(editing: $editing, onSettings: { showSettings = true })
        default: ClockPage(editing: $editing, onSettings: { showSettings = true })
        }
    }

    /// 鍵盤 Option：叫出或關閉音樂介面（沒有歌曲時打開音樂資料庫）。
    private func toggleMusicInterface() {
        guard settings.hasSeenWelcome, !alarm.ringing, !editing, !showSettings else { return }
        if music.showLibrary { music.closeLibrary(); return }
        if musicFull { closeMusic(); return }
        if music.hasItem { openMusic() } else { music.openLibrary() }
    }

    private func closeWelcome() {
        guard !settings.hasSeenWelcome else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { settings.hasSeenWelcome = true }
        startServices()
    }

    private func startServices() {
        weather.start()
        music.start()
    }

    private func openMusic() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { musicFull = true }
    }

    private func closeMusic() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.88)) { musicFull = false }
    }
}
