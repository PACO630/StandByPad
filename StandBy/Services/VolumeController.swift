import SwiftUI
import UIKit
import AVFoundation
import MediaPlayer

/// 系統音量（含 AirPlay 裝置）。
///
/// 直接把 MPVolumeView 放在畫面上時，AirPlay 切換或重新連線的瞬間，系統常會短暫回報音量 0，
/// 音量條就會「跳到 0」。這裡改成自己畫音量條：讀取系統音量時，AirPlay 下突然出現的 0
/// 要在 1.2 秒後再確認一次才採用；設定音量則透過隱藏的 MPVolumeView 滑桿，AirPlay 裝置也能調整。
final class VolumeController: ObservableObject {
    static let shared = VolumeController()

    @Published private(set) var volume: Float = AVAudioSession.sharedInstance().outputVolume
    @Published private(set) var hudVisible = false
    @Published private(set) var isAirPlay = false

    private weak var slider: UISlider?
    private var observation: NSKeyValueObservation?
    private var lastUserChange = Date.distantPast
    private var pendingZero: DispatchWorkItem?
    private var hideHUD: DispatchWorkItem?
    private var started = false

    func start() {
        activateSession()
        guard !started else { return }
        started = true
        volume = AVAudioSession.sharedInstance().outputVolume
        observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let v = change.newValue else { return }
            DispatchQueue.main.async { self?.received(v) }
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.updateRoute()
        }
        updateRoute()
    }

    /// 用不打斷「音樂」App 的 ambient＋mixWithOthers 工作階段，才收得到音量變化。
    func activateSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.ambient, options: [.mixWithOthers])
        try? s.setActive(true)
    }

    func attach(_ slider: UISlider) { self.slider = slider }

    private func updateRoute() {
        isAirPlay = AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .airPlay }
    }

    private func received(_ v: Float) {
        // AirPlay 下、使用者沒有剛調整、音量從有聲突然變 0：先不採用，稍後再確認。
        if v < 0.001, volume > 0.05, isAirPlay, Date().timeIntervalSince(lastUserChange) > 1.5 {
            pendingZero?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let now = AVAudioSession.sharedInstance().outputVolume
                let sliderValue = self.slider?.value ?? now
                if now < 0.001 && sliderValue < 0.001 { self.volume = 0 }
            }
            pendingZero = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
            return
        }
        pendingZero?.cancel()
        pendingZero = nil
        volume = v
    }

    func set(_ value: Float, showHUD: Bool = false) {
        let v = min(max(value, 0), 1)
        lastUserChange = Date()
        pendingZero?.cancel()
        volume = v
        if let slider {
            slider.setValue(v, animated: false)
            slider.sendActions(for: .valueChanged)
        }
        if showHUD { flashHUD() }
    }

    /// 一次調整 1/16（和實體音量鍵相同的級距）。
    func step(_ direction: Int, showHUD: Bool = true) {
        set(volume + Float(direction) / 16, showHUD: showHUD)
    }

    private func flashHUD() {
        hideHUD?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { hudVisible = true }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.easeOut(duration: 0.35)) { self?.hudVisible = false }
        }
        hideHUD = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }
}

/// 隱藏的 MPVolumeView：提供可以調整系統（含 AirPlay）音量的滑桿，並讓系統不跳出音量提示。
struct HiddenSystemVolume: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView(frame: CGRect(x: -100, y: -100, width: 40, height: 40))
        v.alpha = 0.0001
        v.isUserInteractionEnabled = false
        DispatchQueue.main.async { Self.attachSlider(in: v) }
        return v
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        Self.attachSlider(in: uiView)
    }

    private static func attachSlider(in v: MPVolumeView) {
        if let s = v.subviews.compactMap({ $0 as? UISlider }).first {
            VolumeController.shared.attach(s)
        }
    }
}

/// 全螢幕播放器裡的音量條。
struct VolumeBar: View {
    @ObservedObject private var volume = VolumeController.shared
    @State private var dragging = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: volume.volume < 0.01 ? "speaker.slash.fill" : "speaker.fill")
                .font(.system(size: 17))
                .frame(width: 22)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.25))
                    Capsule().fill(Color.white.opacity(0.9))
                        .frame(width: max(g.size.height, g.size.width * CGFloat(volume.volume)))
                        .opacity(volume.volume < 0.01 ? 0 : 1)
                }
                .frame(height: dragging ? 12 : 7)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if !dragging { withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { dragging = true } }
                        volume.set(Float(v.location.x / max(g.size.width, 1)))
                    }
                    .onEnded { _ in withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragging = false } })
            }
            .frame(height: 34)
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 17))
        }
        .accessibilityElement()
        .accessibilityLabel("音量")
        .accessibilityValue("\(Int((volume.volume * 100).rounded()))%")
        .accessibilityAdjustableAction { dir in
            volume.step(dir == .increment ? 1 : -1)
        }
    }
}

/// 用鍵盤調整音量時出現在畫面上方的提示。
struct VolumeHUD: View {
    @ObservedObject private var volume = VolumeController.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: volume.volume < 0.01 ? "speaker.slash.fill" : (volume.isAirPlay ? "airplayaudio" : "speaker.wave.2.fill"))
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 24)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.25))
                    Capsule().fill(Color.white)
                        .frame(width: g.size.width * CGFloat(volume.volume))
                }
            }
            .frame(width: 180, height: 8)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Capsule().fill(Color(hex: 0x2C2C2E).opacity(0.95)))
        .animation(.easeOut(duration: 0.15), value: volume.volume)
        .opacity(volume.hudVisible ? 1 : 0)
        .scaleEffect(volume.hudVisible ? 1 : 0.85)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
