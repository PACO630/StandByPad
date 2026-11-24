import SwiftUI
import MediaPlayer
import AVKit

/// 夜間模式：整個畫面轉為單色紅（亮部變紅、黑色維持黑色）。
struct NightTint: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content
            .grayscale(active ? 1 : 0)
            .colorMultiply(active ? Color.nightRed : Color.white)
    }
}

// MARK: - 歡迎畫面

struct WelcomeOverlay: View {
    let onClose: () -> Void
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
            VStack(spacing: 18) {
                HStack(spacing: 22) {
                    Image(systemName: "cloud.sun.fill")
                        .font(.system(size: 40))
                    Image(systemName: "calendar")
                        .font(.system(size: 38, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 26)
                .padding(.vertical, 14)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.45), lineWidth: 2.5))
                .padding(.top, 8)

                Text("歡迎使用待機模式")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)
                Text("查看實用的小工具、展示你喜愛的照片，或顯示完美的時鐘，從遠處也能一目了然。向左或向右滑動即可開始。")
                    .font(.system(size: 18))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 440)
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 34)
            .background(RoundedRectangle(cornerRadius: 38, style: .continuous).fill(Color(hex: 0x262628).opacity(0.94)))
            .overlay(alignment: .topTrailing) {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white.opacity(0.75))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel("關閉")
                .padding(16)
            }
            .scaleEffect(appeared ? 1 : 0.92)
            .opacity(appeared ? 1 : 0)
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if abs(v.translation.width) > 80 { onClose() }
        })
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.82).delay(0.2)) { appeared = true }
        }
    }
}

// MARK: - 正在播放

struct NowPlayingPill: View {
    var playing = true
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: 30, weight: .semibold))
            EqualizerBars(paused: !playing)
                .frame(width: 24, height: 20)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在播放，點兩下以全螢幕顯示")
        .accessibilityAddTraits(.isButton)
    }
}

struct EqualizerBars: View {
    var paused = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: reduceMotion || paused)) { ctx in
            let t = paused ? 0.6 : ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule()
                        .frame(width: 3.5, height: 5 + 15 * abs(sin(t * (2.4 + Double(i) * 0.7) + Double(i) * 1.3)))
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .white
        v.activeTintColor = .systemBlue
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// 全螢幕播放器：專輯封面、音量與 AirPlay、歌名、播放控制與時間軸。
struct MusicFullScreen: View {
    let onClose: () -> Void
    @EnvironmentObject var music: MusicStore
    @GestureState private var drag: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            ZStack {
                background
                HStack(spacing: W * 0.06) {
                    artwork(size: min(H * 0.66, W * 0.42))
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 14) {
                            VolumeBar()
                            RoutePicker().frame(width: 40, height: 40)
                            Button { music.openLibrary() } label: {
                                Image(systemName: "music.note.list")
                                    .font(.system(size: 20, weight: .semibold))
                                    .frame(width: 40, height: 40)
                            }
                            .accessibilityLabel("從資料庫選擇音樂")
                        }
                        .foregroundColor(.white.opacity(0.85))
                        Spacer()
                        Text(music.title ?? "未在播放")
                            .font(.system(size: H * 0.065, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(music.artist ?? "")
                            .font(.system(size: H * 0.045))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                        Spacer()
                        controls(H: H)
                        Spacer()
                        ProgressRow(H: H)
                    }
                    .foregroundColor(.white)
                    .frame(maxHeight: min(H * 0.66, W * 0.42))
                }
                .padding(.horizontal, W * 0.07)
            }
            .frame(width: W, height: H)
            .offset(x: drag.width * 0.3, y: drag.height * 0.5)
            .scaleEffect(1 - min(abs(drag.height) + abs(drag.width), 400) / 4000)
        }
        .gesture(DragGesture(minimumDistance: 20)
            .updating($drag) { v, s, _ in s = v.translation }
            .onEnded { v in
                if abs(v.translation.height) > 110 || abs(v.translation.width) > 160 { onClose() }
            })
    }

    private var background: some View {
        ZStack {
            Color(hex: 0x1A1A1C)
            if let art = music.artwork {
                Image(uiImage: art)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 80)
                    .opacity(0.55)
            }
            Color.black.opacity(0.35)
        }
        .clipped()
    }

    private func artwork(size: CGFloat) -> some View {
        Group {
            if let art = music.artwork {
                Image(uiImage: art).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.sbFill
                    Image(systemName: "music.note").font(.system(size: size * 0.3)).foregroundColor(.sbGray)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.04, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 30, y: 12)
        .scaleEffect(music.isPlaying ? 1 : 0.86)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: music.isPlaying)
        .accessibilityHidden(true)
    }

    private func controls(H: CGFloat) -> some View {
        HStack {
            Spacer()
            Button(action: music.previous) { Image(systemName: "backward.fill") }
                .accessibilityLabel("上一首")
            Spacer()
            Button(action: music.togglePlay) {
                Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: H * 0.12)
            }
            .accessibilityLabel(music.isPlaying ? "暫停" : "播放")
            Spacer()
            Button(action: music.next) { Image(systemName: "forward.fill") }
                .accessibilityLabel("下一首")
            Spacer()
        }
        .font(.system(size: H * 0.085))
        .foregroundColor(.white)
        .buttonStyle(PressScaleStyle())
    }
}

private struct ProgressRow: View {
    let H: CGFloat
    @EnvironmentObject var music: MusicStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let elapsed = music.currentTime
            let total = max(music.duration, 1)
            VStack(spacing: 8) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.25))
                        Capsule().fill(Color.white.opacity(0.85))
                            .frame(width: g.size.width * CGFloat(min(elapsed / total, 1)))
                    }
                }
                .frame(height: 7)
                HStack {
                    Text(format(elapsed))
                    Spacer()
                    Text("-" + format(max(total - elapsed, 0)))
                }
                .font(.system(size: H * 0.026, weight: .medium).monospacedDigit())
                .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    private func format(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - 充電指示

struct ChargingIndicator: View {
    @EnvironmentObject var battery: BatteryStore
    @State private var visible = false
    @State private var fill: CGFloat = 0
    @State private var hideWork: DispatchWorkItem?

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.14), lineWidth: 9)
            Circle()
                .trim(from: 0, to: fill)
                .stroke(Color.sbGreen, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "bolt.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundColor(.sbGreen)
                .scaleEffect(visible ? 1 : 0.4)
        }
        .frame(width: 76, height: 76)
        .opacity(visible ? 1 : 0)
        .scaleEffect(visible ? 1 : 0.7)
        .accessibilityHidden(true)
        .onAppear { if battery.isCharging { show() } }
        .onChange(of: battery.isCharging) { charging in if charging { show() } }
    }

    private func show() {
        hideWork?.cancel()
        fill = 0
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { visible = true }
        withAnimation(.easeOut(duration: 1.1).delay(0.25)) { fill = CGFloat(battery.level) }
        let work = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.6)) { visible = false }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }
}

// MARK: - 鬧鐘響鈴

struct AlarmRingingView: View {
    @EnvironmentObject var alarm: AlarmController
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 30) {
                HStack(spacing: 12) {
                    Image(systemName: "alarm.fill")
                        .foregroundColor(.sbOrange)
                        .scaleEffect(pulse ? 1.15 : 0.95)
                    Text("鬧鐘")
                }
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(.white)
                TimelineView(.everyMinute) { ctx in
                    Text(Fmt.clock(ctx.date))
                        .font(.system(size: 220, weight: .semibold).width(.compressed))
                        .foregroundColor(Color(hex: 0x7BA7F2))
                }
                HStack(spacing: 24) {
                    Button(action: alarm.snooze) {
                        Text("稍後提醒")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.black)
                            .frame(width: 260, height: 70)
                            .background(Capsule().fill(Color.sbOrange))
                    }
                    Button(action: alarm.stop) {
                        Text("停止")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 260, height: 70)
                            .background(Capsule().fill(Color.white.opacity(0.2)))
                    }
                }
                .buttonStyle(PressScaleStyle())
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
